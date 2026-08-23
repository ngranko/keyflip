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
