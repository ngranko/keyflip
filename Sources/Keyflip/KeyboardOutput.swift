import CoreGraphics
import Foundation

/// Rewrites text by synthesizing keys instead of writing through
/// Accessibility: N backspaces, then the replacement typed as Unicode.
///
/// This is the only path that reaches terminals and Electron editors, which
/// render their own text and expose an empty `AXValue`. It is blind — it
/// trusts `TypingSession.typed` to say what is on screen — so it is a fallback
/// behind the Accessibility path, never the default.
enum KeyboardOutput {
    /// Stamped on every event we post so our own tap can ignore them.
    /// Without this the synthesized keys would feed back into the mirror.
    static let marker: Int64 = 0x4B59_464C_5000

    /// `keyboardSetUnicodeString` is reliable for short strings; chunk anything
    /// longer rather than trusting one oversized event.
    private static let chunkSize = 16

    static func replace(deleting count: Int, with text: String) -> Bool {
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

        var units = Array(text.utf16)
        while !units.isEmpty {
            var size = min(chunkSize, units.count)
            // Never end a chunk on a lone high surrogate: split there and both
            // halves of the pair are delivered as garbage.
            if size < units.count, (0xD800...0xDBFF).contains(units[size - 1]) {
                size -= 1
            }
            let chunk = Array(units.prefix(size))
            units.removeFirst(chunk.count)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return false }
            // Only the key-down carries the text. A key-up carrying the same
            // string makes some apps insert it a second time.
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            post(down)
            post(up)
        }
        return true
    }

    private static func post(_ event: CGEvent) {
        // Clear inherited flags explicitly: a stuck modifier would change what
        // every one of these keystrokes means to the receiving app.
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cgSessionEventTap)
    }
}
