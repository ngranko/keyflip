import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import LayoutConversion
import os

/// One filtering CGEvent tap drives the recognizer, the typing session, and
/// the Set-trigger recorder.
///
/// Not an NSEvent monitor: those hand back a non-nil token even when the
/// process is untrusted and will never deliver a keystroke, so `isActive`
/// could not mean anything.
///
/// Everything here runs on the tap's own thread and must stay short. The one
/// rule that outranks every feature: an event this app cannot deal with right
/// now goes through untouched (ADR 0009).
final class EventTap: @unchecked Sendable {
    var onTrigger: (() -> Void)?

    let session = TypingSession()
    let recognizer: TriggerRecognizer

    /// A panel left open — or an app that stalled with one open — must not go
    /// on swallowing the keyboard.
    private static let recordingLimit: TimeInterval = 60

    private var port: TapPort!
    private let lock = NSLock()
    /// Stamped before anything that could fail or wait, so it witnesses the
    /// keystroke even when the rest of the callback declines to touch it.
    private let lastKeyDown = OSAllocatedUnfairLock(initialState: TimeInterval(0))
    private var recorder: Recorder?
    private var recordingExpiry: TimeInterval = 0
    private var onRecorded: ((Recorder.Result) -> Void)?

    var isActive: Bool { port.isActive }

    /// Given up on for this launch, rather than refused by the system.
    var isRetired: Bool { port.isRetired }

    /// What the live tap may do to an event, in the words the log uses. The
    /// first question to ask of any report of stuck input.
    var modeDescription: String {
        switch port.mode {
        case .listenOnly: return "listen only"
        case .defaultTap: return "may delete"
        default: return "none"
        }
    }

    private static let mask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue)
        | (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue)
        | (1 << CGEventType.otherMouseDown.rawValue)

    init(trigger: Trigger, interval: TimeInterval) {
        recognizer = TriggerRecognizer(trigger: trigger, interval: interval)
        port = TapPort(mask: Self.mask) { [weak self] type, event in
            guard let self else { return Unmanaged.passUnretained(event) }
            return self.handle(type: type, event: event)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.session.end()
        }
    }

    @discardableResult
    func start() -> Bool {
        witnessKeyDown()
        return port.start(neededMode())
    }

    /// Hands the tap over on evidence it is holding input; see `TapPort`.
    func giveUp(_ reason: String) { port.giveUp(reason) }

    /// How long since a keystroke reached this tap.
    var secondsSinceKeyDown: TimeInterval {
        ProcessInfo.processInfo.systemUptime - lastKeyDown.withLock { $0 }
    }

    /// Leaves the process with no way to touch anyone's input.
    func stop() {
        port.stop()
        session.end()
        stopRecording()
        recognizer.reset()
    }

    func rearm() { port.rearm() }

    func setTrigger(_ trigger: Trigger) {
        lock.lock()
        recognizer.trigger = trigger
        recognizer.reset()
        lock.unlock()
        matchModeToWork()
    }

    /// What this app needs the tap to be allowed to do.
    ///
    /// A tap that may only listen cannot hold anyone's keyboard, whatever goes
    /// wrong in this process (ADR 0009), so it is preferred wherever it will
    /// do. Creating one raises the Input Monitoring dialog, but the access
    /// itself rides on the Accessibility grant this app must have anyway to
    /// read a field: with `ListenEvent` reset to undecided, this still
    /// preflights true, and a process without Accessibility preflights false.
    /// So the check is what decides, never the dialog — declining it costs
    /// nothing today, and the day a macOS separates the two, this degrades to
    /// an active tap by itself rather than losing the tap.
    private func neededMode() -> CGEventTapOptions {
        guard !mustDeleteEvents(), CGPreflightListenEventAccess() else { return .defaultTap }
        return .listenOnly
    }

    /// A chord trigger's key must fire without also typing its character, and
    /// the Set-trigger panel swallows keys so binding ⌘Q does not quit the app
    /// underneath it. A double-tap — the default — deletes nothing, ever.
    private func mustDeleteEvents() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if recorder != nil { return true }
        if case .chord = recognizer.trigger { return true }
        return false
    }

    /// A tap cannot be given new powers, only replaced by one that has them.
    private func matchModeToWork() {
        let wanted = neededMode()
        guard let mode = port.mode, mode != wanted else { return }
        DebugLog.event("tap mode → \(wanted == .listenOnly ? "listen only" : "may delete")")
        port.stop()
        port.start(wanted)
    }

    /// While recording, keystrokes go to the recorder and are swallowed, so
    /// binding ⌘Q does not quit the app underneath the panel.
    func startRecording(interval: TimeInterval, onResult: @escaping (Recorder.Result) -> Void) {
        lock.lock()
        onRecorded = onResult
        recorder = Recorder(interval: interval)
        recordingExpiry = ProcessInfo.processInfo.systemUptime + Self.recordingLimit
        lock.unlock()
        matchModeToWork()
    }

    func stopRecording() {
        lock.lock()
        endRecording()
        lock.unlock()
        matchModeToWork()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)
        if type == .keyDown { witnessKeyDown() }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DebugLog.event("tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
            port.recoverFromDisable(type)
            return passthrough
        }

        // Our own synthesized backspaces and text must not feed back into the
        // typing mirror or the recognizer.
        if event.getIntegerValueField(.eventSourceUserData) == KeyboardOutput.marker {
            return passthrough
        }

        guard let tapEvent = TapEvent(type: type, event: event) else { return passthrough }

        // Never wait for the lock: whoever holds it, the keystroke reaches the
        // front app rather than queueing behind this process.
        guard lock.try() else { return passthrough }
        defer { lock.unlock() }
        return decide(tapEvent, passing: passthrough)
    }

    private func decide(
        _ tapEvent: TapEvent,
        passing passthrough: Unmanaged<CGEvent>
    ) -> Unmanaged<CGEvent>? {
        let now = ProcessInfo.processInfo.systemUptime
        if recorder != nil {
            return record(tapEvent, at: now, passing: passthrough)
        }
        if recognizer.handle(tapEvent, at: now) == .fired {
            DebugLog.event("trigger fired session=\(session.isLive)")
            DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
            // Swallow a chord so ⌥L fires the trigger instead of typing "¬".
            // A double-tap fires on a modifier release, which must pass through.
            return tapEvent.kind == .keyDown ? nil : passthrough
        }
        session.handle(tapEvent)
        return passthrough
    }

    private func record(
        _ tapEvent: TapEvent,
        at now: TimeInterval,
        passing passthrough: Unmanaged<CGEvent>
    ) -> Unmanaged<CGEvent>? {
        guard let recorder, now < recordingExpiry else {
            DebugLog.event("recording outlived its panel → keys pass through")
            endRecording(reporting: .cancel)
            return passthrough
        }
        let result = recorder.handle(tapEvent, at: now)
        if result != .none {
            let report = onRecorded
            DispatchQueue.main.async { report?(result) }
        }
        return tapEvent.kind == .mouseDown ? passthrough : nil
    }

    private func witnessKeyDown() {
        let now = ProcessInfo.processInfo.systemUptime
        lastKeyDown.withLock { $0 = now }
    }

    /// Caller holds the lock.
    private func endRecording(reporting result: Recorder.Result = .none) {
        let report = onRecorded
        recorder = nil
        onRecorded = nil
        recordingExpiry = 0
        guard result != .none else { return }
        DispatchQueue.main.async { report?(result) }
    }
}

private extension TapEvent {
    init?(type: CGEventType, event: CGEvent) {
        let kind: Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .flagsChanged: kind = .flagsChanged
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: kind = .mouseDown
        default: return nil
        }
        self.init(
            kind: kind,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            characters: kind == .keyDown ? event.typedCharacters : ""
        )
    }
}

private extension CGEvent {
    /// What the system resolved this keystroke to, layout and dead keys
    /// already applied — no second guess at `UCKeyTranslate` needed.
    var typedCharacters: String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: min(length, buffer.count))
    }
}
