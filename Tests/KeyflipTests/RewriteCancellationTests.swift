import ApplicationServices
import Foundation
import LayoutConversion
import Testing
@testable import Keyflip

@MainActor
private final class DeferredWait: Wait {
    var work: [() -> Void] = []
    func after(_ delay: TimeInterval, then work: @escaping () -> Void) { self.work.append(work) }
    func advance() { if !work.isEmpty { work.removeFirst()() } }
}

private final class ChangingField: FieldReader {
    var state: FieldRead
    init(_ snapshot: FieldSnapshot) { state = .field(snapshot) }
    func read() -> FieldRead { state }
    func isFocused(_ snapshot: FieldSnapshot) -> Bool {
        guard case .field(let current) = state else { return false }
        return current.handle.matches(snapshot.handle)
    }
}

@MainActor
private final class RewriteScenario {
    let original = snapshot(reading(value: "ghbdtn", caret: 6))
    let session = TypingSession()
    let writer = ScriptedWriter()
    let wait = DeferredWait()
    let reader: ChangingField
    let rewriter: FieldRewriter
    var results: [Bool] = []

    init() {
        reader = ChangingField(original)
        rewriter = FieldRewriter(session: session,
                                 reader: reader, writer: writer, wait: wait)
        session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "ghbdtn"))
    }

    func start() {
        rewriter.rewrite(Target(text: "ghbdtn", range: NSRange(location: 0, length: 6)),
                         to: "привет", in: original) { self.results.append($0.shouldFollow) }
    }
}

@MainActor
@Test func cancelConfirmationWhenFocusDisappears() {
    let scenario = RewriteScenario()
    scenario.writer.verifyAnswers = [.unchanged]
    scenario.start()
    let calls = scenario.writer.calls
    scenario.reader.state = .noFocus
    scenario.wait.advance()
    #expect(scenario.writer.calls == calls)
    #expect(scenario.results == [false])
    #expect(!scenario.rewriter.isSettling)
}

@MainActor
@Test func cancelWhenAnotherFieldInTheSameAppGetsFocus() {
    let scenario = RewriteScenario()
    scenario.writer.verifyAnswers = [.unchanged]
    scenario.start()
    var other = scenario.original
    other.handle = .ax(AXUIElementCreateApplication(1))
    scenario.reader.state = .field(other)
    scenario.wait.advance()
    #expect(scenario.writer.verifyCount == 1)
    #expect(scenario.results == [false])
}

@MainActor
@Test func cancelRetryAfterUserTypes() {
    let scenario = RewriteScenario()
    scenario.writer.verifyAnswers = [.unchanged]
    scenario.start()
    scenario.session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "x"))
    scenario.wait.advance()
    #expect(scenario.writer.verifyCount == 1)
    #expect(scenario.results == [false])
    #expect(scenario.session.typed == "ghbdtnx")
}

@MainActor
@Test func cancelCaretRetryAfterAClick() {
    let scenario = RewriteScenario()
    scenario.writer.replaceAnswers = [.refused]
    scenario.writer.selectAnswers = [false]
    scenario.writer.restoreCaretAnswers = [.selectionHeld]
    scenario.start()
    let calls = scenario.writer.calls
    scenario.session.handle(TapEvent(kind: .mouseDown, keyCode: 0, flags: 0))
    scenario.wait.advance()
    #expect(scenario.writer.calls == calls)
    #expect(scenario.results == [false])
}

@MainActor
@Test func stopRecoveryWithoutFallingBackToAnOldSnapshot() {
    let scenario = RewriteScenario()
    scenario.writer.replaceAnswers = [.declined]
    var truncated = scenario.original
    truncated.reading.value = "gh"
    scenario.reader.state = .field(truncated)
    scenario.start()
    for _ in 0..<12 { scenario.wait.advance() }
    #expect(scenario.writer.calls == [.replace(NSRange(location: 0, length: 6), "привет")])
    #expect(scenario.results == [false])
    #expect(!scenario.rewriter.isSettling)
}

@MainActor
@Test func doNotRepairIntoAnotherFieldOrFollowAfterFocusMoves() {
    let scenario = RewriteScenario()
    scenario.writer.replaceAnswers = [.refused]
    scenario.start()
    let calls = scenario.writer.calls
    var other = scenario.original
    other.handle = .ax(AXUIElementCreateApplication(1))
    other.reading.value = ""
    scenario.reader.state = .field(other)
    scenario.wait.advance()
    #expect(scenario.writer.calls == calls)
    #expect(scenario.results == [false])
}

@MainActor
@Test func stopBeforeWritingWhenTheInitialSnapshotIsStale() {
    let scenario = RewriteScenario()
    scenario.reader.state = .secure
    scenario.start()
    #expect(scenario.writer.calls.isEmpty)
    #expect(scenario.results == [false])
}

@MainActor
@Test func doNotFollowAfterNewInputDuringMirrorSettle() {
    let scenario = RewriteScenario()
    scenario.rewriter.typeOverMirror((text: "ghbdtn", trailing: ""), as: "привет", in: scenario.original) {
        scenario.results.append($0.shouldFollow)
    }
    scenario.session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "x"))
    scenario.wait.advance()
    #expect(scenario.results == [false])
    #expect(scenario.writer.calls == [.typeKeys(deleting: 6, with: "привет")])
}

@MainActor
@Test func recheckOwnershipAfterSettingASelection() {
    let scenario = RewriteScenario()
    scenario.writer.replaceAnswers = [.refused]
    scenario.writer.onSelect = { scenario.reader.state = .noFocus }
    scenario.start()
    #expect(!scenario.writer.calls.contains(.typeKeys(deleting: 0, with: "привет")))
    #expect(scenario.results == [false])
}

@MainActor
@Test func rejectInputThatArrivedWhileTheSnapshotWasRead() {
    let scenario = RewriteScenario()
    var original = scenario.original
    original.inputRevision = scenario.session.inputRevision
    scenario.session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "x"))
    scenario.rewriter.rewrite(Target(text: "ghbdtn", range: NSRange(location: 0, length: 6)),
                              to: "привет", in: original) { scenario.results.append($0.shouldFollow) }
    #expect(scenario.writer.calls.isEmpty)
    #expect(scenario.results == [false])
}

@MainActor
@Test func rewriteFreshTypingInATerminalWithNoReadableValue() {
    let original = snapshot(reading(app: "cmux", value: "", caret: 0))
    let session = TypingSession()
    for character in "ghbdtn " {
        session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: String(character)))
    }
    let verdict = TargetSelection.choose(in: original.reading, session: session) { _ in }
    guard case .mirror(let text, let trailing) = verdict else {
        Issue.record("Fresh terminal typing must reach the mirror rewrite")
        return
    }
    let writer = ScriptedWriter()
    let rewriter = FieldRewriter(session: session,
                                 reader: ChangingField(original), writer: writer, wait: ImmediateWait())
    var result: Bool?
    rewriter.typeOverMirror((text: text, trailing: trailing), as: "привет", in: original) { result = $0.shouldFollow }
    #expect(result == true)
    #expect(writer.calls == [.typeKeys(deleting: 7, with: "привет ")])
    #expect(session.typed == "привет ")
}
