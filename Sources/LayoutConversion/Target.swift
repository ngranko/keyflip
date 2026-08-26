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

    /// Whether the field and the typing mirror tell the same story about the
    /// text in front of the caret. Nil when they agree; both readings when
    /// they do not.
    ///
    /// They can only disagree if one of them is wrong, and the caret is the
    /// usual culprit. Zen reports `AXSelectedTextRange` offsets that run behind
    /// its own `AXValue` in a multi-line field — ten short, in the case that
    /// found this — so a caret sitting at the end of the text arrives pointing
    /// into a word the user finished minutes ago. Converting there rewrites
    /// text nobody touched, and `sessionUTF16` makes it worse rather than
    /// better: it carries the right width to the wrong place, clipping a
    /// bystander word to the length of the word that should have been
    /// converted.
    ///
    /// An empty mirror agrees with everything — it is the "no opinion" case,
    /// not a contradiction, and so is a field with nothing in front of the
    /// caret to read. A mirror longer than the text in front of the caret is
    /// compared over the overlap, which is all a field with a truncated
    /// `AXValue` can offer.
    public static func caretDisagreement(
        with mirror: String,
        in text: String,
        caretUTF16: Int
    ) -> (field: String, mirror: String)? {
        let mirrorNS = mirror as NSString
        guard mirrorNS.length > 0 else { return nil }
        let ns = text as NSString
        let caret = max(0, min(caretUTF16, ns.length))
        let overlap = min(mirrorNS.length, caret)
        // Nothing to compare is not a contradiction. A field that reads back
        // empty — a terminal, an Electron editor — has no opinion about the
        // caret, and the mirror is meant to be the only witness there.
        guard overlap > 0 else { return nil }
        let field = ns.substring(with: NSRange(location: caret - overlap, length: overlap))
        let tail = mirrorNS.substring(from: mirrorNS.length - overlap)
        return field == tail ? nil : (field: field, mirror: tail)
    }
}

extension TextRange {
    /// Whether a range is the whole of what the text says, give or take
    /// whitespace around it.
    ///
    /// The question a caller asks before replacing a field wholesale: if
    /// nothing but padding lies outside the range, there is nothing outside
    /// the range to lose.
    public static func spansEverything(_ range: NSRange, in text: String) -> Bool {
        let ns = text as NSString
        guard range.location >= 0, range.length >= 0, range.upperBound <= ns.length else {
            return false
        }
        return ns.substring(to: range.location).allSatisfy(\.isWhitespace)
            && ns.substring(from: range.upperBound).allSatisfy(\.isWhitespace)
    }
}
