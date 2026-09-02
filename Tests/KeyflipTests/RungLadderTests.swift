import Foundation
import LayoutConversion
import Testing
@testable import Keyflip

private let app = "Cursor"
private let target = Target(text: "сщьз", range: NSRange(location: 0, length: 4))
private let output = "comp"

private func field(showing value: String) -> FieldReading {
    FieldReading(
        app: app,
        role: "AXTextArea",
        value: value,
        selectedRange: NSRange(location: 0, length: 0),
        selectedText: ""
    )
}

private func field(selecting selectedText: String = "") -> FieldReading {
    FieldReading(
        app: app,
        role: "AXTextArea",
        value: "сщьз",
        selectedRange: NSRange(location: 0, length: selectedText.isEmpty ? 0 : 4),
        selectedText: selectedText
    )
}

private func liveSession(typing text: String) -> TypingSession {
    let session = TypingSession()
    for character in text {
        session.handle(
            TapEvent(kind: .keyDown, keyCode: 0x00, flags: 0, characters: String(character))
        )
    }
    return session
}

@MainActor
private struct Ladder {
    let writer: ScriptedWriter
    let settings: SettingsStore
    let rewriter: FieldRewriter
    let reading: FieldReading

    init(
        writer: ScriptedWriter,
        selecting selectedText: String = "",
        mirror: String = "",
        alreadyRefused: Set<String> = [],
        readsBack: FieldReading? = nil
    ) {
        let defaults = UserDefaults(suiteName: "KeyflipRungTests")!
        defaults.removePersistentDomain(forName: "KeyflipRungTests")
        let settings = SettingsStore(defaults: defaults)
        settings.axWriteRefused = alreadyRefused
        self.writer = writer
        self.settings = settings
        self.reading = field(selecting: selectedText)
        self.rewriter = FieldRewriter(
            settings: settings,
            session: liveSession(typing: mirror),
            reader: readsBack.map { ScriptedField(showing: [$0]) } ?? ScriptedField(always: reading),
            writer: writer,
            wait: ImmediateWait()
        )
    }

    /// The ladder runs to the end before this returns, because every wait is
    /// taken immediately.
    func run() -> Bool {
        var landed: Bool?
        rewriter.rewrite(
            target,
            to: output,
            in: FieldSnapshot(handle: .none, reading: reading)
        ) { landed = $0 }
        return landed ?? false
    }
}

@MainActor
@Test func aWriteTheAppConfirmsStopsAtTheFirstRung() {
    let writer = ScriptedWriter()
    writer.verifyAnswers = [.applied]
    let ladder = Ladder(writer: writer)
    #expect(ladder.run())
    #expect(writer.calls == [.replace(target.range, output), .verify])
    #expect(ladder.settings.axWriteRefused.isEmpty)
}

/// ADR 0006: a selection the user made is typed over, never written through —
/// the write buys nothing and fragments the element tree the lower rungs need.
@MainActor
@Test func aSelectionTheUserMadeIsTypedOverRatherThanWritten() {
    let writer = ScriptedWriter()
    let ladder = Ladder(writer: writer, selecting: target.text)
    #expect(ladder.run())
    #expect(writer.calls == [
        .select(target.range, target.text),
        .typeKeys(deleting: 0, with: output),
    ])
}

/// ADR 0007: an app part-way through applying a write reads back as neither
/// text for a frame or two, so the check is retried before it is believed.
@MainActor
@Test func aWriteStillInFlightIsRecheckedBeforeItIsCalledARefusal() {
    let writer = ScriptedWriter()
    writer.verifyAnswers = [.unchanged, .unchanged, .applied]
    let ladder = Ladder(writer: writer)
    #expect(ladder.run())
    #expect(writer.verifyCount == 3)
    #expect(ladder.settings.axWriteRefused.isEmpty)
}

/// Monaco discards the write and says nothing. Once the rechecks run out the
/// app goes on the retype list and the keystroke path takes over.
@MainActor
@Test func aWriteThatNeverLandsIsRememberedAndRetyped() {
    let writer = ScriptedWriter()
    writer.verifyAnswers = [.unchanged]
    let ladder = Ladder(writer: writer)
    #expect(ladder.run())
    #expect(writer.verifyCount == 6)
    #expect(ladder.settings.axWriteRefused == [app])
    #expect(writer.calls.contains(.select(target.range, target.text)))
}

/// A field reading back as neither text is not proof of damage — Monaco
/// truncates under exactly these conditions — so it goes the same way.
@MainActor
@Test func aMangledReadbackIsHandedToTheKeystrokePath() {
    let writer = ScriptedWriter()
    writer.verifyAnswers = [.mangled("щтдн")]
    let ladder = Ladder(writer: writer)
    #expect(ladder.run())
    #expect(ladder.settings.axWriteRefused == [app])
    #expect(writer.calls.contains(.typeKeys(deleting: 0, with: output)))
}

/// A field that will not read back at all tells us nothing, and retyping over
/// a write that did land would double the run.
@MainActor
@Test func anUnreadableFieldIsAssumedWrittenRatherThanRetyped() {
    let writer = ScriptedWriter()
    writer.verifyAnswers = [.unreadable]
    let ladder = Ladder(writer: writer)
    #expect(ladder.run())
    #expect(writer.calls == [.replace(target.range, output), .verify])
    #expect(ladder.settings.axWriteRefused.isEmpty)
}

/// The app was never asked, so there is no refusal to remember. Recording one
/// would send every later conversion there down the blind path.
@MainActor
@Test func aDeclinedWriteRemembersNothing() {
    let writer = ScriptedWriter()
    writer.replaceAnswers = [.declined]
    let ladder = Ladder(writer: writer)
    #expect(ladder.run())
    #expect(ladder.settings.axWriteRefused.isEmpty)
}

/// ADR 0007: the cost of learning an app refuses is paid once, ever. The next
/// launch skips the write that poisons the element.
@MainActor
@Test func aKnownRefusingAppIsNeverWrittenToAgain() {
    let writer = ScriptedWriter()
    let ladder = Ladder(writer: writer, alreadyRefused: [app])
    #expect(ladder.run())
    #expect(!writer.calls.contains(.replace(target.range, output)))
    #expect(!writer.calls.contains(.verify))
}

/// The bottom rung: no selection to type over, so backspaces counted from the
/// mirror, and only from a caret the field proves collapsed.
@MainActor
@Test func theBlindRungErasesByTheMirrorsCount() {
    let writer = ScriptedWriter()
    writer.selectAnswers = [false]
    let ladder = Ladder(writer: writer, mirror: target.text, alreadyRefused: [app])
    #expect(ladder.run())
    #expect(writer.calls.contains(.typeKeys(deleting: 4, with: output)))
}

/// A refused write can leave its selection behind, and one backspace against
/// that eats the whole run — so the blind rung backs out instead.
@MainActor
@Test func theBlindRungBacksOutWhenTheCaretIsNotCollapsed() {
    let writer = ScriptedWriter()
    writer.selectAnswers = [false]
    writer.restoreCaretAnswers = [false]
    let ladder = Ladder(writer: writer, mirror: target.text, alreadyRefused: [app])
    #expect(!ladder.run())
    #expect(!writer.calls.contains(.typeKeys(deleting: 4, with: output)))
}

/// Nothing to count against: the mirror does not describe the target, so the
/// blind rung declines rather than deleting by a guess.
@MainActor
@Test func theBlindRungDeclinesWithoutAMatchingMirror() {
    let writer = ScriptedWriter()
    writer.selectAnswers = [false]
    let ladder = Ladder(writer: writer, mirror: "something else", alreadyRefused: [app])
    #expect(!ladder.run())
}

/// The Slack failure this was written for: the backspaces landed, the text
/// meant to replace them never arrived, and the field settled empty. An empty
/// field is the one readback where typing the words again cannot double them.
@MainActor
@Test func textTheFieldLostIsTypedAgain() {
    let writer = ScriptedWriter()
    writer.selectAnswers = [false]
    let ladder = Ladder(
        writer: writer,
        mirror: target.text,
        alreadyRefused: [app],
        readsBack: field(showing: "")
    )
    #expect(ladder.run())
    #expect(writer.calls.contains(.typeKeys(deleting: 4, with: output)))
    #expect(writer.calls.filter { $0 == .typeKeys(deleting: 0, with: output) }.count == 1)
}

/// A field that came back holding something else is a diagnosis, not a loss:
/// typing over text we cannot account for is how the words get doubled.
@MainActor
@Test func textTheFieldReplacedWithSomethingElseIsLeftAlone() {
    let writer = ScriptedWriter()
    writer.selectAnswers = [false]
    let ladder = Ladder(
        writer: writer,
        mirror: target.text,
        alreadyRefused: [app],
        readsBack: field(showing: "что-то ещё")
    )
    #expect(ladder.run())
    #expect(!writer.calls.contains(.typeKeys(deleting: 0, with: output)))
}
