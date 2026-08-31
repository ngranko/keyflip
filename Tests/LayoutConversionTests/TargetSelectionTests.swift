import Foundation
import Testing
@testable import LayoutConversion

private func reading(
    value: String,
    caret: Int,
    selectionLength: Int = 0,
    selectedText: String = ""
) -> FieldReading {
    FieldReading(
        app: "TestApp",
        role: "AXTextArea",
        value: value,
        selectedRange: NSRange(location: caret, length: selectionLength),
        selectedText: selectedText
    )
}

private func session(typing text: String) -> TypingSession {
    let session = TypingSession()
    for character in text {
        session.handle(
            TapEvent(kind: .keyDown, keyCode: 0x00, flags: 0, characters: String(character))
        )
    }
    return session
}

private final class Notes {
    var collected: [TargetNote] = []
    func take(_ note: TargetNote) { collected.append(note) }
}

@discardableResult
private func choose(
    _ reading: FieldReading,
    typing mirror: String = "",
    notes: Notes = Notes()
) -> TargetVerdict {
    TargetSelection.choose(in: reading, session: session(typing: mirror), note: notes.take)
}

@Test func aSelectionWinsOutrightOverALiveSession() {
    let verdict = choose(
        reading(
            value: "привет мир",
            caret: 0,
            selectionLength: 6,
            selectedText: "привет"
        ),
        typing: "агдд"
    )
    #expect(verdict == .field(Target(text: "привет", range: NSRange(location: 0, length: 6))))
}

@Test func aSelectedRangeWithNoTextIsSlicedFromTheValue() {
    let verdict = choose(reading(value: "hello world", caret: 6, selectionLength: 5))
    #expect(verdict == .field(Target(text: "world", range: NSRange(location: 6, length: 5))))
}

@Test func aSelectedRangeRunningPastTheValueIsClamped() {
    let verdict = choose(reading(value: "hello", caret: 3, selectionLength: 99))
    #expect(verdict == .field(Target(text: "lo", range: NSRange(location: 3, length: 2))))
}

@Test func aDeadSessionWithNoSelectionHasNoTarget() {
    let notes = Notes()
    let verdict = choose(reading(value: "hello", caret: 5), notes: notes)
    #expect(verdict == TargetVerdict.none)
    #expect(notes.collected == [.noTarget(sessionLive: false)])
}

/// ADR 0008, from the log: `focal-length-data-` was already in the field and
/// the session typed `агдд`. The run is one hyphenated token, so without the
/// clip the whole identifier converts and the vote drags it the wrong way.
@Test func theSessionClipsARunItOnlyFinished() {
    let field = reading(value: "focal-length-data-агдд", caret: 22)
    let verdict = choose(field, typing: "агдд")
    #expect(verdict == .field(Target(text: "агдд", range: NSRange(location: 18, length: 4))))
}

/// ADR 0007: Zen reports a caret running behind its own value. The mirror is
/// not at the end of the field either, so erasing by its count would eat text
/// it never saw.
@Test func aCaretPointingSomewhereElseEntirelyRewritesNothing() {
    let notes = Notes()
    let verdict = choose(reading(value: "hello world", caret: 11), typing: "xyz", notes: notes)
    #expect(verdict == .unusable)
    #expect(notes.collected == [.caretDisagreed(field: "rld", mirror: "xyz", keptMirror: false)])
}

/// The same disagreement, but the mirror *is* the end of the field: the caret
/// is the liar, and keystrokes use the real one.
@Test func aLyingCaretOverAMirrorAtTheEndFallsToTheMirror() {
    let notes = Notes()
    let verdict = choose(reading(value: "abcполе", caret: 3), typing: "поле", notes: notes)
    #expect(verdict == .mirror(text: "поле", trailing: ""))
    #expect(notes.collected == [.caretDisagreed(field: "abc", mirror: "оле", keptMirror: true)])
}

/// ADR 0006: Monaco resyncs mid-word and answers with one `(` where the line
/// reads `Ищщдуфт(`. Both witnesses agree over the character they share, so
/// only the run reaching past the value's start tells them apart.
@Test func aValueHoldingOnlyTheTailOfTheRunFallsToTheMirror() {
    let notes = Notes()
    let verdict = choose(reading(value: "(", caret: 1), typing: "Ищщдуфт(", notes: notes)
    #expect(verdict == .mirror(text: "Ищщдуфт(", trailing: ""))
    #expect(notes.collected == [.fieldHidesStartOfRun(mirror: "Ищщдуфт(")])
}

/// The mirror keeps its trailing space so the run before it can be found, and
/// hands both halves over for the keystroke path to erase.
@Test func theMirrorHandsOverTheTrailingSpaceItKept() {
    let verdict = choose(reading(value: "", caret: 0), typing: "ghbdtn ")
    #expect(verdict == .mirror(text: "ghbdtn", trailing: " "))
}
