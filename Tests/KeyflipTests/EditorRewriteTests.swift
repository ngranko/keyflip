import Foundation
import LayoutConversion
import Testing
@testable import Keyflip

@MainActor
private final class EditorScenario {
    let editor: EditorModel
    let session = TypingSession()
    let wait = ManualWait()
    let rewriter: FieldRewriter
    var results: [RewriteOutcome] = []

    init(_ text: String) {
        editor = EditorModel(text)
        rewriter = FieldRewriter(session: session,
                                 reader: editor, writer: editor, wait: wait)
        session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: text))
    }

    func rewrite(_ text: String, to output: String) {
        let range = (editor.current.reading.value as NSString).range(of: text)
        rewriter.rewrite(Target(text: text, range: range), to: output, in: editor.current) {
            self.results.append($0)
        }
    }

    func deliver() { editor.deliver(); wait.advance() }
}

@MainActor
@Test func confirmedWritesPreserveSpaceCaretAndMirrorAcrossRepeatedConversions() {
    let scenario = EditorScenario("prefix ghbdtn  ")
    scenario.rewrite("ghbdtn", to: "привет")
    #expect(scenario.results.isEmpty)
    #expect(scenario.rewriter.isSettling)
    scenario.deliver()
    #expect(scenario.results == [.applied])
    #expect(scenario.editor.current.reading.value == "prefix привет  ")
    #expect(scenario.session.typed == "prefix привет  ")
    #expect(scenario.editor.current.reading.selectedRange.location == 15)
    scenario.rewrite("привет", to: "ghbdtn")
    scenario.deliver()
    #expect(scenario.editor.current.reading.value == "prefix ghbdtn  ")
    #expect(scenario.session.typed == "prefix ghbdtn  ")
}

@MainActor
@Test func aDelayedKeyReplacementMustActuallyReplaceTheOriginal() {
    let scenario = EditorScenario("ghbdtn")
    scenario.editor.acceptsAX = false
    scenario.editor.insertWithoutReplacing = true
    scenario.rewrite("ghbdtn", to: "привет")
    scenario.deliver()
    #expect(scenario.editor.current.reading.value == "приветghbdtn")
    #expect(scenario.results == [.unknown])
    #expect(scenario.editor.keyWrites == 1)
    #expect(scenario.session.typed.isEmpty)
}

@MainActor
@Test func repairIsConfirmedOnlyAfterItsOwnDelivery() {
    let scenario = EditorScenario("ghbdtn")
    scenario.editor.acceptsAX = false
    scenario.editor.dropNextInsertion = true
    scenario.rewrite("ghbdtn", to: "привет")
    scenario.deliver()
    #expect(scenario.editor.current.reading.value.isEmpty)
    #expect(scenario.results.isEmpty)
    #expect(scenario.editor.keyWrites == 2)
    scenario.deliver()
    #expect(scenario.results == [.applied])
    #expect(scenario.editor.current.reading.value == "привет")
}

@MainActor
@Test func repeatedTriggerCannotInterleaveWithPendingEditorDelivery() {
    let scenario = EditorScenario("ghbdtn")
    scenario.rewrite("ghbdtn", to: "привет")
    scenario.rewrite("ghbdtn", to: "привет")
    #expect(scenario.results == [.failed])
    scenario.deliver()
    #expect(scenario.results == [.failed, .applied])
    #expect(scenario.editor.current.reading.value == "привет")
}

@MainActor
@Test func refusalsExpireAndStayWithinTheSameField() {
    var time: TimeInterval = 0
    let cache = WriteRefusals(lifetime: 10, now: { time })
    let first = snapshot(reading(app: "one", value: "x", caret: 1))
    var other = snapshot(reading(app: "two", value: "x", caret: 1))
    other.reading.app = first.reading.app
    cache.noteFailure(first)
    #expect(!cache.shouldSkip(first))
    cache.noteFailure(first)
    #expect(cache.shouldSkip(first))
    #expect(!cache.shouldSkip(other))
    time = 11
    #expect(!cache.shouldSkip(first))
    cache.noteFailure(first)
    cache.noteFailure(first)
    cache.noteSuccess(first)
    #expect(!cache.shouldSkip(first))
}

@MainActor
@Test func anUnreadableSelectionDoesNotInheritTheTerminalFollowPolicy() {
    let selected = snapshot(reading(value: "", caret: 0, selectionLength: 6, selectedText: "ghbdtn"))
    let writer = ScriptedWriter()
    let reader = ScriptedField(always: selected.reading)
    let rewriter = FieldRewriter(session: TypingSession(),
                                 reader: reader, writer: writer, wait: ImmediateWait())
    var outcome: RewriteOutcome?
    rewriter.rewrite(Target(text: "ghbdtn", range: selected.reading.selectedRange), to: "привет", in: selected) {
        outcome = $0
    }
    #expect(outcome == .unknown)
    #expect(writer.calls.filter { $0 == .typeKeys(deleting: 0, with: "привет") }.count == 1)
}

@MainActor
@Test(arguments: [true, false])
func delayedRewritesMoveCaretToEndBeforeContinuedTyping(usesAX: Bool) {
    let scenario = EditorScenario("🙂 ghbdtn suffix")
    scenario.editor.acceptsAX = usesAX
    scenario.editor.leavesCaretAtStart = true
    scenario.rewrite("ghbdtn", to: "привет🙂")
    scenario.deliver()
    #expect(scenario.results == [.applied])
    #expect(scenario.editor.current.reading.selectedRange == NSRange(location: 11, length: 0))
    _ = scenario.editor.typeKeys(deleting: 0, with: "!")
    scenario.editor.deliver()
    #expect(scenario.editor.current.reading.value == "🙂 привет🙂! suffix")
}

@MainActor
@Test func delayedCaretRestorationRetriesWithoutRewritingText() {
    let scenario = EditorScenario("ghbdtn  ")
    scenario.editor.leavesCaretAtStart = true
    scenario.editor.refusedCaretMoves = 2
    scenario.rewrite("ghbdtn", to: "привет")
    scenario.deliver()
    #expect(scenario.results.isEmpty)
    #expect(scenario.rewriter.isSettling)
    scenario.wait.advance()
    scenario.wait.advance()
    #expect(scenario.results == [.applied])
    #expect(scenario.editor.current.reading.selectedRange == NSRange(location: 8, length: 0))
    #expect(scenario.editor.current.reading.value == "привет  ")
    #expect(scenario.editor.keyWrites == 0)
}

@MainActor
@Test func userTypingCancelsPendingCaretRestoration() {
    let scenario = EditorScenario("ghbdtn")
    scenario.editor.leavesCaretAtStart = true
    scenario.editor.refusedCaretMoves = 1
    scenario.rewrite("ghbdtn", to: "привет")
    scenario.deliver()
    scenario.session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "x"))
    scenario.wait.advance()
    #expect(scenario.results == [.failed])
    #expect(scenario.editor.caretMoves == 1)
}

@MainActor
@Test func refusedCaretRestorationDoesNotRetypeConfirmedText() {
    let scenario = EditorScenario("ghbdtn")
    scenario.editor.leavesCaretAtStart = true
    scenario.editor.refusedCaretMoves = 20
    scenario.rewrite("ghbdtn", to: "привет")
    scenario.deliver()
    for _ in 0..<FieldRewriter.confirmAttempts { scenario.wait.advance() }
    #expect(scenario.results == [.unknown])
    #expect(scenario.editor.current.reading.value == "привет")
    #expect(scenario.editor.keyWrites == 0)
    #expect(scenario.session.typed.isEmpty)
}
