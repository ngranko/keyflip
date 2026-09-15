import Foundation

/// The mirror is written from the event tap's own thread and read from the
/// main one, so every entry point takes the lock. Nothing inside it does more
/// than touch a string: a keystroke can wait on that, and never longer.
public final class TypingSession: @unchecked Sendable {
    private enum Key {
        static let backspace: UInt16 = 0x33
        static let forwardDelete: UInt16 = 0x75
    }

    /// Far more than a word, still bounded.
    private static let limit = 256

    private let lock = NSLock()
    private var live = false
    private var mirror = ""
    private var revision: UInt64 = 0
    private var lastReset: SessionResetReason?
    private let onReset: @Sendable (SessionReset) -> Void

    public var inputRevision: UInt64 { locked { revision } }

    public var isLive: Bool { locked { live } }

    /// A best-effort mirror of what the app received since the session began —
    /// the only witness in fields Accessibility cannot read. Empty whenever it
    /// cannot be trusted.
    public var typed: String { locked { mirror } }

    public init(onReset: @escaping @Sendable (SessionReset) -> Void = { _ in }) {
        self.onReset = onReset
    }

    public func end(reason: SessionResetReason = .explicit) {
        report(locked {
            revision &+= 1
            return reset(reason: reason)
        })
    }

    // Internal rewrites change the mirror without witnessing new user input.
    public func discardMirror() { report(locked { reset(reason: .mirrorDiscarded) }) }

    /// Keep the mirror in step after synthesized keys have been sent.
    public func replaceTail(_ count: Int, with text: String) {
        report(locked {
            // Erasing more than the mirror holds means it never described the
            // field, and the blind path would later delete by that guess.
            guard count <= mirror.count else {
                return reset(reason: .mirrorMismatch)
            }
            mirror.removeLast(count)
            mirror += text
            return nil
        })
    }

    public func handle(_ event: TapEvent) {
        report(locked {
            switch event.kind {
            case .mouseDown:
                revision &+= 1
                return reset(reason: .mouseDown)
            case .flagsChanged, .keyUp:
                return nil
            case .keyDown:
                revision &+= 1
                return handleKeyDown(event)
            }
        })
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func reset(reason: SessionResetReason) -> SessionReset? {
        let changed = live || !mirror.isEmpty || lastReset != reason
        let reset = SessionReset(reason: reason, wasLive: live, mirroredUTF16: mirror.utf16.count, revision: revision)
        live = false
        mirror = ""
        lastReset = reason
        return changed ? reset : nil
    }

    private func report(_ reset: SessionReset?) {
        // Logging must never execute while the typing-state lock is held.
        if let reset { onReset(reset) }
    }

    /// Callers hold the lock.
    private func handleKeyDown(_ event: TapEvent) -> SessionReset? {
        if let reason = chooseResetReason(for: event) {
            return reset(reason: reason)
        }
        if event.keyCode == Key.backspace {
            // Backspace never starts a session, but it does shorten one.
            if live, !mirror.isEmpty {
                mirror.removeLast()
            }
            return mirror.isEmpty ? reset(reason: .backspaceExhausted) : nil
        }
        if Self.isTypable(event.characters) {
            live = true
            lastReset = nil
            mirror += event.characters
            if mirror.count > Self.limit {
                mirror.removeFirst(mirror.count - Self.limit)
            }
        } else {
            // Unknown input cannot authorize edits to text from an earlier session.
            return reset(reason: event.characters.isEmpty ? .emptyKeyText : .nonTextKey)
        }
        return nil
    }

    /// Text the app would have inserted. Excludes control characters and the
    /// private-use scalars AppKit hands out for arrows and function keys.
    private static func isTypable(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
        }
    }

    private func chooseResetReason(for event: TapEvent) -> SessionResetReason? {
        if event.keyCode == Key.backspace, event.independentFlags & Trigger.relevantModifiers != 0 {
            return .modifiedDeletion
        }
        if event.independentFlags & ((1 << 20) | (1 << 18)) != 0 { return .shortcut }
        if event.keyCode == Key.forwardDelete { return .forwardDelete }
        if isCaretMoving(event.keyCode) { return .caretMovement }
        if isCommitOrCancel(event.keyCode) { return .commitOrCancel }
        return nil
    }

    private func isCaretMoving(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79:
            return true
        default:
            return false
        }
    }

    /// Return, keypad Enter, Tab, Esc.
    private func isCommitOrCancel(_ keyCode: UInt16) -> Bool {
        keyCode == 0x24 || keyCode == 0x4C || keyCode == 0x30 || keyCode == 0x35
    }
}

extension TypingSession {
    /// The same "last run of non-whitespace, trailing space skipped" rule the
    /// field path uses, read from the mirror. Nil while the mirror has nothing
    /// a rewrite could be counted against.
    public var lastRun: (text: String, trailing: String)? {
        let (live, mirror) = locked { (self.live, self.mirror) }
        guard live,
              let word = LastWord.range(in: mirror, caretUTF16: (mirror as NSString).length)
        else { return nil }
        let ns = mirror as NSString
        return (ns.substring(with: word), ns.substring(from: word.upperBound))
    }
}
