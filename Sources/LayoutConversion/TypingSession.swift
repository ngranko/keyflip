import Foundation

public final class TypingSession: @unchecked Sendable {
    private enum Key {
        static let backspace: UInt16 = 0x33
        static let forwardDelete: UInt16 = 0x75
    }

    /// Far more than a word, still bounded.
    private static let limit = 256

    public private(set) var isLive = false

    /// A best-effort mirror of what the app received since the session began.
    ///
    /// This is what lets conversion work in fields Accessibility cannot read —
    /// terminals and Electron editors render their own text and expose an empty
    /// `AXValue`. Empty whenever the mirror cannot be trusted, in which case
    /// only the Accessibility path can find a target.
    public private(set) var typed = ""

    public init() {}

    public func end() {
        isLive = false
        typed = ""
    }

    /// Keep the mirror in step after synthesized keys have been sent.
    public func replaceTail(_ count: Int, with text: String) {
        guard count <= typed.count else {
            typed = text
            return
        }
        typed.removeLast(count)
        typed += text
    }

    public func handle(_ event: TapEvent) {
        switch event.kind {
        case .mouseDown:
            end()
        case .flagsChanged:
            break
        case .keyDown:
            handleKeyDown(event)
        }
    }

    private func handleKeyDown(_ event: TapEvent) {
        if isShortcut(event) || isCaretMoving(event.keyCode) || isReturnOrTabOrEsc(event.keyCode) {
            end()
            return
        }
        if event.keyCode == Key.forwardDelete {
            end()
            return
        }
        if event.keyCode == Key.backspace {
            // Backspace never starts a session, but it does shorten one.
            if isLive, !typed.isEmpty {
                typed.removeLast()
            }
            return
        }
        isLive = true
        if Self.isTypable(event.characters) {
            typed += event.characters
            if typed.count > Self.limit {
                typed.removeFirst(typed.count - Self.limit)
            }
        } else {
            // A key that produced no text we can account for. The mirror no
            // longer matches the field, so stop offering it.
            typed = ""
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

    private func isCaretMoving(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79:
            return true
        default:
            return false
        }
    }

    private func isReturnOrTabOrEsc(_ keyCode: UInt16) -> Bool {
        keyCode == 0x24 || keyCode == 0x4C || keyCode == 0x30 || keyCode == 0x35
    }
}
