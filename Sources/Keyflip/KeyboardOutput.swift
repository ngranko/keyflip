import CoreGraphics
import Foundation

/// N backspaces, then the replacement typed as Unicode.
///
/// Blind — it trusts `TypingSession.typed` to say what is on screen — so it is
/// the fallback behind the Accessibility path, and the only path that reaches
/// a terminal.
enum KeyboardOutput {
    /// Stamped on every event we post, so our own tap can ignore them rather
    /// than feed them back into the mirror.
    static let marker: Int64 = 0x4B59_464C_5000

    /// `keyboardSetUnicodeString` is reliable for short strings; chunk anything
    /// longer rather than trusting one oversized event.
    private static let chunkSize = 16

    static func replace(deleting count: Int, with text: String) -> Bool {
        guard count >= 0, count <= 4096, text.utf16.count <= 4096 else { return false }
        guard count > 0 || !text.isEmpty else { return true }
        // A private source does not inherit the modifiers the user is holding.
        // Inheriting Option here would turn every backspace into delete-word.
        guard let source = CGEventSource(stateID: .privateState) else {
            DebugLog.event("keys: no event source")
            return false
        }

        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
            else { return false }
            post(down)
            post(up)
        }

        for chunk in chunkUnicode(text) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return false }
            // Only the key-down carries the text. A key-up carrying the same
            // string makes some apps insert it a second time.
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: Array(chunk))
            post(down)
            post(up)
        }
        return true
    }

    static func chunkUnicode(_ text: String) -> [ArraySlice<UInt16>] {
        let units = Array(text.utf16)
        var chunks: [ArraySlice<UInt16>] = []
        var start = 0
        while start < units.count {
            var end = min(start + chunkSize, units.count)
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
            chunks.append(units[start..<end])
            start = end
        }
        return chunks
    }

    private static func post(_ event: CGEvent) {
        // Clear inherited flags explicitly: a stuck modifier would change what
        // every one of these keystrokes means to the receiving app.
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cgSessionEventTap)
    }
}
