import Foundation
@testable import LayoutConversion
import Testing

@Test func lastRunSkipsTrailingSpace() {
    let text = "hello world "
    let caret = (text as NSString).length
    #expect(LastWord.substring(in: text, caretUTF16: caret) == "world")
}

@Test func lastRunAtEndOfWord() {
    let text = "hello world"
    let caret = (text as NSString).length
    #expect(LastWord.substring(in: text, caretUTF16: caret) == "world")
}

@Test func lastRunFromMiddleOfWordIsThePrefix() {
    let text = "hello world"
    let caret = (text as NSString).range(of: "r").location
    #expect(LastWord.substring(in: text, caretUTF16: caret) == "wo")
}

@Test func emptyOrWhitespaceHasNoLastWord() {
    #expect(LastWord.range(in: "", caretUTF16: 0) == nil)
    #expect(LastWord.range(in: "   ", caretUTF16: 3) == nil)
}

@Test func punctuationStaysInsideTheRun() {
    let text = "hello, "
    let caret = (text as NSString).length
    #expect(LastWord.substring(in: text, caretUTF16: caret) == "hello,")
}

@Test func sessionClipsARunThatStartedBeforeIt() {
    // Half the word was typed, the field was left and re-entered, and only
    // "агдд" belongs to the session that is live now.
    let text = "focal-length-data-агдд"
    let caret = (text as NSString).length
    #expect(LastWord.substring(in: text, caretUTF16: caret, sessionUTF16: 4) == "агдд")
}

@Test func sessionCoveringTheWholeRunLeavesItWhole() {
    let text = "hello ghjgf"
    let caret = (text as NSString).length
    #expect(LastWord.substring(in: text, caretUTF16: caret, sessionUTF16: 5) == "ghjgf")
    #expect(LastWord.substring(in: text, caretUTF16: caret, sessionUTF16: 99) == "ghjgf")
}

@Test func sessionThatTypedOnlyWhitespaceHasNoTarget() {
    let text = "прив "
    let caret = (text as NSString).length
    #expect(LastWord.range(in: text, caretUTF16: caret, sessionUTF16: 1) == nil)
}

@Test func unknownSessionExtentLeavesTheRunWhole() {
    let text = "focal-length-data-агдд"
    let caret = (text as NSString).length
    #expect(LastWord.substring(in: text, caretUTF16: caret, sessionUTF16: nil) == text)
}

// MARK: - Caret against the typing mirror

@Test func anAgreeingCaretHasNoDisagreement() {
    let text = "hello ghjgf"
    let caret = (text as NSString).length
    #expect(LastWord.caretDisagreement(with: "ghjgf", in: text, caretUTF16: caret) == nil)
}

@Test func anEmptyMirrorHasNoOpinion() {
    #expect(LastWord.caretDisagreement(with: "", in: "hello world", caretUTF16: 11) == nil)
}

@Test func aCaretShortOfWhatWasTypedIsADisagreement() {
    // Zen, 2026-08-25: the field reported its caret ten UTF-16 units behind
    // where the text actually ended, so the run in front of it was a word the
    // user had finished earlier. Here in miniature: the caret lands after
    // "also," while the mirror knows the last four characters typed were
    // "огые" at the very end.
    let text = "x also, огые"
    let staleCaret = 7

    // What the old path built from that caret — a bystander word, clipped to
    // the width of the word that should have been converted.
    #expect(LastWord.substring(in: text, caretUTF16: staleCaret, sessionUTF16: 4) == "lso,")

    let clash = LastWord.caretDisagreement(with: "огые", in: text, caretUTF16: staleCaret)
    #expect(clash?.field == "lso,")
    #expect(clash?.mirror == "огые")
}

@Test func aMirrorLongerThanTheFieldIsComparedOverTheOverlap() {
    // Monaco hands back only the trailing token, so the mirror reaches back
    // further than AXValue does. The overlap is all there is to check.
    #expect(LastWord.caretDisagreement(with: "hello ghjgf", in: "ghjgf", caretUTF16: 5) == nil)
    #expect(LastWord.caretDisagreement(with: "hello ghjgf", in: "abcde", caretUTF16: 5) != nil)
}

@Test func aFieldWithNothingToReadHasNoOpinionEither() {
    // The terminal and Electron case: AXValue comes back empty and the mirror
    // is the only witness. Silence is not a contradiction.
    #expect(LastWord.caretDisagreement(with: "abc", in: "", caretUTF16: 3) == nil)
    #expect(LastWord.caretDisagreement(with: "abc", in: "abc", caretUTF16: 0) == nil)
}

// MARK: - A value that starts mid-run

@Test func aValueHoldingOnlyTheTailOfWhatWasTypedHidesTheRun() {
    // Cursor, 2026-08-27: Monaco resynced its textarea as “(” was typed and
    // read back holding nothing else, so the run converted to itself and the
    // word behind it was never touched.
    #expect(LastWord.hidesStartOfRun(from: "Ищщдуфт(", in: "(", caretUTF16: 1))

    // And the mirror is worth asking only while it knows more: the same run in
    // both witnesses hides nothing.
    #expect(!LastWord.hidesStartOfRun(from: "ghjgf", in: "ghjgf", caretUTF16: 5))
    #expect(!LastWord.hidesStartOfRun(from: "", in: "ghjgf", caretUTF16: 5))
}

@Test func aRunTheFieldStartsAfterAWordBreakIsWhole() {
    // The field puts a space in front of the run, so the run is all there is
    // to convert — a mirror reaching back past that break has drifted, and
    // erasing by its length would eat the word before.
    #expect(!LastWord.hidesStartOfRun(from: "hello ghjgf", in: "say ghjgf", caretUTF16: 9))
}

@Test func aRunTheMirrorDoesNotEndInIsNotHidden() {
    // The field got shorter on its own — cleared, or rewritten by an
    // autocompletion. What it shows is not the tail of what was typed, so the
    // field is the only witness left worth taking at its word.
    #expect(!LastWord.hidesStartOfRun(from: "кудумфте", in: "relevant", caretUTF16: 8))
}

// MARK: - Whether a range is the whole field

@Test func aRangeCoveringEverythingSpansTheValue() {
    #expect(TextRange.spansEverything(NSRange(location: 0, length: 7), in: "кудуфыу"))
}

@Test func paddingAroundTheRangeStillSpansTheValue() {
    #expect(TextRange.spansEverything(NSRange(location: 1, length: 6), in: " cceofz \n"))
}

@Test func textOutsideTheRangeDoesNotSpanTheValue() {
    // The 460-character Zen message: everything but the four-character target
    // is content a whole-value write would have to reproduce exactly.
    #expect(!TextRange.spansEverything(NSRange(location: 446, length: 4), in: String(repeating: "a", count: 460)))
    #expect(!TextRange.spansEverything(NSRange(location: 6, length: 5), in: "hello world"))
}

@Test func aRangeOutsideTheTextSpansNothing() {
    #expect(!TextRange.spansEverything(NSRange(location: 5, length: 10), in: "hello"))
    #expect(!TextRange.spansEverything(NSRange(location: -1, length: 2), in: "hello"))
}
