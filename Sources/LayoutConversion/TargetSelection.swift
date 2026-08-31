import Foundation

/// The text conversion rewrites, and where it sits in the field.
public struct Target: Equatable, Sendable {
    public var text: String
    public var range: NSRange

    public init(text: String, range: NSRange) {
        self.text = text
        self.range = range
    }
}

/// What the trigger has to work with. `none` and `unusable` both end in a
/// layout toggle, but they are not the same answer: `none` is the plainest
/// no-target there is, while `unusable` is the two witnesses contradicting
/// each other so completely that neither can say where the target is.
public enum TargetVerdict: Equatable, Sendable {
    case field(Target)
    case mirror(text: String, trailing: String)
    case none
    case unusable
}

/// What decided a verdict. Carried out as a value rather than logged here, so
/// the module stays free of the log while the lines it produces — the whole
/// diagnosis for the field bugs in ADR 0006 and 0007 — stay exactly as they
/// were.
public enum TargetNote: Equatable, Sendable {
    case caretDisagreed(field: String, mirror: String, keptMirror: Bool)
    case fieldHidesStartOfRun(mirror: String)
    case noTarget(sessionLive: Bool)
}

/// Which text a trigger rewrites, weighed from both witnesses: the field, and
/// the mirror of what was typed.
///
/// Neither witness is reliable on its own. The field is exact where
/// Accessibility reaches it and silent where it does not; the caret it reports
/// can run behind its own value. The mirror always has something to say and is
/// wrong the moment a key produced text it could not account for. Every rule
/// below exists because one of them lied in a way the other could catch.
public enum TargetSelection {
    /// A non-empty selection always wins. Otherwise the last run of
    /// non-whitespace, and only while a typing session is live (ADR 0002) and
    /// the field agrees with the mirror about what is in front of the caret.
    public static func choose(
        in reading: FieldReading,
        session: TypingSession,
        note: (TargetNote) -> Void
    ) -> TargetVerdict {
        if let selected = takeSelection(in: reading) {
            return .field(selected)
        }
        guard session.isLive else { return askTheMirror(session, note: note) }
        return weighWitnesses(reading, session: session, note: note)
    }

    /// A selection the user made is the target outright, whether the field
    /// hands over its text or only its range.
    private static func takeSelection(in reading: FieldReading) -> Target? {
        if !reading.selectedText.isEmpty {
            return Target(text: reading.selectedText, range: reading.selectedRange)
        }
        guard reading.selectedRange.length > 0 else { return nil }
        let range = TextRange.clamp(reading.selectedRange, in: reading.value)
        guard range.length > 0 else { return nil }
        return Target(text: (reading.value as NSString).substring(with: range), range: range)
    }

    private static func weighWitnesses(
        _ reading: FieldReading,
        session: TypingSession,
        note: (TargetNote) -> Void
    ) -> TargetVerdict {
        let mirror = session.typed
        let caret = reading.selectedRange.location
        let clash = LastWord.caretDisagreement(
            with: mirror,
            in: reading.value,
            caretUTF16: caret
        )
        if let clash {
            return settle(clash, in: reading, mirror: mirror, session: session, note: note)
        }
        if LastWord.hidesStartOfRun(from: mirror, in: reading.value, caretUTF16: caret) {
            // Converting what the field shows would convert “(” to itself and
            // leave the word behind it (Cursor, 2026-08-27).
            note(.fieldHidesStartOfRun(mirror: mirror))
            return askTheMirror(session, note: note)
        }
        guard let word = LastWord.range(
            in: reading.value,
            caretUTF16: caret,
            sessionUTF16: extent(of: mirror)
        ) else { return askTheMirror(session, note: note) }
        return .field(Target(
            text: (reading.value as NSString).substring(with: word.nsRange),
            range: word.nsRange
        ))
    }

    /// If the mirror's text is at the end of the field after all, the caret is
    /// the liar but keystrokes still land, since they use the real one — so
    /// drop ranges and keep the mirror. If it is nowhere in the field, the
    /// field transformed what was typed (smart quotes) and erasing by the
    /// mirror's count would eat text it never saw.
    private static func settle(
        _ clash: (field: String, mirror: String),
        in reading: FieldReading,
        mirror: String,
        session: TypingSession,
        note: (TargetNote) -> Void
    ) -> TargetVerdict {
        let mirrored = reading.value.hasSuffix(mirror)
        note(.caretDisagreed(field: clash.field, mirror: clash.mirror, keptMirror: mirrored))
        return mirrored ? askTheMirror(session, note: note) : .unusable
    }

    /// The mirror is the only witness in the terminals and Electron editors
    /// that hand back an empty value.
    private static func askTheMirror(
        _ session: TypingSession,
        note: (TargetNote) -> Void
    ) -> TargetVerdict {
        guard let run = session.lastRun else {
            note(.noTarget(sessionLive: session.isLive))
            return .none
        }
        return .mirror(text: run.text, trailing: run.trailing)
    }

    /// How much of the text in front of the caret this session typed, for
    /// `LastWord.range` to clip to (ADR 0008). Nil once the mirror has been
    /// emptied by a key we could not account for: clipping to zero would
    /// refuse everything.
    private static func extent(of mirror: String) -> Int? {
        let length = (mirror as NSString).length
        return length > 0 ? length : nil
    }
}
