import Foundation
import LayoutConversion
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
