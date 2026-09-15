import Foundation
import LayoutConversion
import Testing

private func chooseAfter(_ events: [TapEvent], value: String) -> TargetVerdict {
    let session = TypingSession()
    for event in events { session.handle(event) }
    let reading = FieldReading(app: "Test", role: "AXTextField", value: value,
                               selectedRange: NSRange(location: value.utf16.count, length: 0), selectedText: "")
    return TargetSelection.choose(in: reading, session: session) { _ in }
}

@Test func modifiedBackspaceCannotAuthorizeBlindDeletion() {
    let session = TypingSession()
    session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "hello world"))
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x33, flags: 1 << 19))
    #expect(session.lastRun == nil)
    #expect(!session.isLive)
}

@Test func deletingTheEntireSessionCannotSelectOlderText() {
    let verdict = chooseAfter([
        TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "x"),
        TapEvent(kind: .keyDown, keyCode: 0x33, flags: 0),
    ], value: "existing")
    #expect(verdict == .none)
}

@Test func unknownInputCannotSelectOlderText() {
    let verdict = chooseAfter([
        TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "x"),
        TapEvent(kind: .keyDown, keyCode: 0x60, flags: 0, characters: "\u{F708}"),
    ], value: "existingx")
    #expect(verdict == .none)
}

@Test func newTypingAfterAnExhaustedSessionOnlySelectsNewText() {
    let verdict = chooseAfter([
        TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "x"),
        TapEvent(kind: .keyDown, keyCode: 0x33, flags: 0),
        TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "abc"),
    ], value: "existingabc")
    #expect(verdict == .field(Target(text: "abc", range: NSRange(location: 8, length: 3))))
}
