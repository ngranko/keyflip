import Foundation

public struct TextRange: Equatable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public var nsRange: NSRange { NSRange(location: location, length: length) }
}

public enum LastWord {
    /// The run of non-whitespace in front of the caret, optionally clipped to
    /// the part of it the current typing session put there.
    ///
    /// A run can straddle a session boundary: type half of a word, leave the
    /// field, come back and finish it in the wrong layout. Converting the whole
    /// run then rewrites text that was already right — and because from-source
    /// is decided by a vote, a longer correct prefix drags the whole word into
    /// the wrong layout, which is worse than not converting at all.
    ///
    /// `sessionUTF16` is how much this session typed. Pass nil to take the
    /// whole run, which is all that can be done when the session's extent is
    /// not known.
    public static func range(
        in text: String,
        caretUTF16: Int,
        sessionUTF16: Int? = nil
    ) -> TextRange? {
        let ns = text as NSString
        let caret = max(0, min(caretUTF16, ns.length))
        guard caret > 0 else { return nil }

        let prefix = ns.substring(to: caret) as String
        var end = prefix.endIndex
        while end > prefix.startIndex {
            let prev = prefix.index(before: end)
            if prefix[prev].isWhitespace {
                end = prev
            } else {
                break
            }
        }
        guard end > prefix.startIndex else { return nil }

        var start = end
        while start > prefix.startIndex {
            let prev = prefix.index(before: start)
            if prefix[prev].isWhitespace { break }
            start = prev
        }

        let startUTF16 = prefix[..<start].utf16.count
        let endUTF16 = prefix[..<end].utf16.count
        // Never reach back past where the session began. A mirror longer than
        // the text in front of the caret has drifted, and max() leaves the run
        // whole rather than trusting it.
        let from = sessionUTF16.map { max(startUTF16, caret - max(0, $0)) } ?? startUTF16
        let length = endUTF16 - from
        guard length > 0 else { return nil }
        return TextRange(location: from, length: length)
    }

    public static func substring(
        in text: String,
        caretUTF16: Int,
        sessionUTF16: Int? = nil
    ) -> String? {
        guard let range = range(in: text, caretUTF16: caretUTF16, sessionUTF16: sessionUTF16) else {
            return nil
        }
        return (text as NSString).substring(with: range.nsRange)
    }
}
