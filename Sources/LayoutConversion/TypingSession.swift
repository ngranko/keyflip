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

    public var isLive: Bool { locked { live } }

    /// A best-effort mirror of what the app received since the session began —
    /// the only witness in fields Accessibility cannot read. Empty whenever it
    /// cannot be trusted.
    public var typed: String { locked { mirror } }

    public init() {}

    public func end() {
        locked { reset() }
    }

    /// Keep the mirror in step after synthesized keys have been sent.
    public func replaceTail(_ count: Int, with text: String) {
        locked {
            // Erasing more than the mirror holds means it never described the
            // field, and the blind path would later delete by that guess.
            guard count <= mirror.count else {
                reset()
                return
            }
            mirror.removeLast(count)
            mirror += text
        }
    }

    public func handle(_ event: TapEvent) {
        locked {
            switch event.kind {
            case .mouseDown:
                reset()
            case .flagsChanged:
                break
            case .keyDown:
                handleKeyDown(event)
            }
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func reset() {
        live = false
        mirror = ""
    }

    /// Callers hold the lock.
    private func handleKeyDown(_ event: TapEvent) {
        if isShortcut(event) || endsTheRun(event.keyCode) {
            reset()
            return
        }
        if event.keyCode == Key.backspace {
            // Backspace never starts a session, but it does shorten one.
            if live, !mirror.isEmpty {
                mirror.removeLast()
            }
            return
        }
        live = true
        if Self.isTypable(event.characters) {
            mirror += event.characters
            if mirror.count > Self.limit {
                mirror.removeFirst(mirror.count - Self.limit)
            }
        } else {
            // No text we can account for, so the mirror no longer matches.
            mirror = ""
        }
    }

    /// Text the app would have inserted. Excludes control characters and the
    /// private-use scalars AppKit hands out for arrows and function keys.
    private static func isTypable(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
        }
    }

    private func isShortcut(_ event: TapEvent) -> Bool {
        let command = event.independentFlags & (1 << 20) != 0
        let control = event.independentFlags & (1 << 18) != 0
        return command || control
    }

    /// Keys after which the mirror would describe text the caret is no longer
    /// in front of.
    private func endsTheRun(_ keyCode: UInt16) -> Bool {
        keyCode == Key.forwardDelete || isCaretMoving(keyCode) || isCommitOrCancel(keyCode)
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
