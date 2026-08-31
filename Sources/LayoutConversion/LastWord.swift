import Foundation

enum LastWord {
    /// The run of non-whitespace in front of the caret, clipped to the part of
    /// it `sessionUTF16` says this typing session put there. Nil takes the
    /// whole run.
    ///
    /// Clipping matters because from-source is decided by a vote: a run that
    /// straddles a session boundary carries a correct prefix long enough to
    /// drag the whole word into the wrong layout.
    static func range(
        in text: String,
        caretUTF16: Int,
        sessionUTF16: Int? = nil
    ) -> NSRange? {
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
        // A mirror longer than the text in front of the caret has drifted;
        // max() leaves the run whole rather than reaching back past its start.
        let from = sessionUTF16.map { max(startUTF16, caret - max(0, $0)) } ?? startUTF16
        let length = endUTF16 - from
        guard length > 0 else { return nil }
        return NSRange(location: from, length: length)
    }

    static func substring(
        in text: String,
        caretUTF16: Int,
        sessionUTF16: Int? = nil
    ) -> String? {
        guard let range = range(in: text, caretUTF16: caretUTF16, sessionUTF16: sessionUTF16) else {
            return nil
        }
        return (text as NSString).substring(with: range)
    }

    /// Whether the field and the typing mirror disagree about the text in front
    /// of the caret. Nil when they agree; both readings when they do not.
    ///
    /// The caret is the usual liar: Zen reports `AXSelectedTextRange` offsets
    /// that run behind its own `AXValue` in a multi-line field — ten short, in
    /// the case that found this — so a caret sitting at the end of the text
    /// arrives pointing into a word finished minutes ago.
    ///
    /// An empty mirror, or nothing in front of the caret, is no opinion rather
    /// than a contradiction. A longer mirror is compared over the overlap.
    static func caretDisagreement(
        with mirror: String,
        in text: String,
        caretUTF16: Int
    ) -> (field: String, mirror: String)? {
        let mirrorNS = mirror as NSString
        guard mirrorNS.length > 0 else { return nil }
        let ns = text as NSString
        let caret = max(0, min(caretUTF16, ns.length))
        let overlap = min(mirrorNS.length, caret)
        guard overlap > 0 else { return nil }
        let field = ns.substring(with: NSRange(location: caret - overlap, length: overlap))
        let tail = mirrorNS.substring(from: mirrorNS.length - overlap)
        return field == tail ? nil : (field: field, mirror: tail)
    }

    /// Whether the field is showing only the tail of a run whose start just the
    /// mirror can see.
    ///
    /// Monaco resyncs its hidden textarea mid-word and can come back holding
    /// one “(” where the line reads “Ищщдуфт(”. Both witnesses agree over the
    /// character they share, so the caret check passes and the run converts to
    /// itself. The tell is the mirror's run reaching past where the value
    /// begins — a run that genuinely got shorter does not end in what the
    /// field shows.
    static func hidesStartOfRun(
        from mirror: String,
        in text: String,
        caretUTF16: Int
    ) -> Bool {
        guard let visible = range(in: text, caretUTF16: caretUTF16),
              visible.location == 0,
              let typed = range(in: mirror, caretUTF16: (mirror as NSString).length)
        else { return false }
        let shown = (text as NSString).substring(with: visible)
        let whole = (mirror as NSString).substring(with: typed)
        return whole.count > shown.count && whole.hasSuffix(shown)
    }
}
