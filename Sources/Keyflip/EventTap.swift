import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import LayoutConversion

/// One filtering CGEvent tap drives everything: the trigger recognizer, the
/// typing session, and the Set-trigger recorder.
///
/// A filtering tap needs Accessibility, which the app already needs to read and
/// write text, so there is no second NSEvent path to keep in sync — and
/// `isActive` can mean the one thing that matters: the tap exists. Global
/// NSEvent monitors are the trap here; they hand back a non-nil token even when
/// the process is untrusted and will never deliver a keystroke.
final class EventTap: @unchecked Sendable {
    var onTrigger: (() -> Void)?

    let session = TypingSession()
    let recognizer: TriggerRecognizer

    private var port: CFMachPort?
    private var recorder: Recorder?
    private var onRecorded: ((Recorder.Result) -> Void)?
    private var loggedFailure = false

    var isActive: Bool { port != nil }

    private static let mask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.flagsChanged.rawValue)
        | (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue)
        | (1 << CGEventType.otherMouseDown.rawValue)

    init(trigger: Trigger, interval: TimeInterval) {
        recognizer = TriggerRecognizer(trigger: trigger, interval: interval)
    }

    /// Idempotent, so the launch retry loop can keep calling it until the
    /// Accessibility grant lands.
    @discardableResult
    func start() -> Bool {
        if isActive { return true }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<EventTap>.fromOpaque(info)
                    .takeUnretainedValue()
                    .handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // The retry loop calls this every couple of seconds; say it once.
            if !loggedFailure {
                loggedFailure = true
                DebugLog.event("tap create failed (accessibility=\(AXIsProcessTrusted())) — retrying")
            }
            return false
        }
        loggedFailure = false

        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        // The tap lives as long as the process; nothing ever unregisters this.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.session.end()
        }

        DebugLog.event("tap active")
        return true
    }

    func setTrigger(_ trigger: Trigger) {
        recognizer.trigger = trigger
        recognizer.reset()
    }

    /// While recording, keystrokes go to the recorder and are swallowed, so
    /// binding ⌘Q does not quit the app underneath the panel.
    func startRecording(interval: TimeInterval, onResult: @escaping (Recorder.Result) -> Void) {
        onRecorded = onResult
        recorder = Recorder(interval: interval)
    }

    func stopRecording() {
        recorder = nil
        onRecorded = nil
        recognizer.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DebugLog.event("tap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return passthrough
        }

        // Our own synthesized backspaces and text must not feed back into the
        // typing mirror or the recognizer.
        if event.getIntegerValueField(.eventSourceUserData) == KeyboardOutput.marker {
            return passthrough
        }

        guard let tapEvent = TapEvent(type: type, event: event) else { return passthrough }
        let now = ProcessInfo.processInfo.systemUptime

        if let recorder {
            let result = recorder.handle(tapEvent, at: now)
            if result != .none {
                DispatchQueue.main.async { [weak self] in self?.onRecorded?(result) }
            }
            return tapEvent.kind == .mouseDown ? passthrough : nil
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
