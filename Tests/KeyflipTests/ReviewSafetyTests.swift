import ApplicationServices
import Foundation
import LayoutConversion
import Testing
@testable import Keyflip

@Test func rejectUnexpectedAccessibilityElementTypes() {
    #expect(FieldAccess.castElement(nil) == nil)
    #expect(FieldAccess.castElement("wrong type" as CFString) == nil)
    #expect(FieldAccess.castElement(42 as CFNumber) == nil)
    let element = AXUIElementCreateApplication(1)
    #expect(FieldAccess.castElement(element).map { CFEqual($0, element) } == true)
}

private final class InterruptingReader: FieldReader {
    var readCount = 0
    var onRead: () -> Void = {}
    var onFocus: () -> Void = {}

    func read() -> FieldRead {
        readCount += 1
        onRead()
        return .unsupported
    }

    func isFocused(_ snapshot: FieldSnapshot) -> Bool {
        onFocus()
        return true
    }
}

@MainActor
@Test func cancelTriggerWhenInputArrivesBeforeDispatchOrDuringRead() {
    let suite = "KeyflipTriggerReview-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = SettingsStore(defaults: defaults)
    let tap = EventTap(trigger: .default, interval: 0.3)
    let reader = InterruptingReader()
    let writer = ScriptedWriter()
    let controller = ConvertController(
        settings: settings, tap: tap,
        pair: Pair(settings: settings, catalog: ScriptedCatalog(enabled: ["a", "b"])),
        reader: reader,
        rewriter: FieldRewriter(session: tap.session, reader: reader, writer: writer, wait: ImmediateWait())
    )
    let revision = tap.session.inputRevision
    let key = TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "x")
    tap.session.handle(key)
    controller.handleTrigger(revision: revision)
    #expect(reader.readCount == 0)
    reader.onRead = { tap.session.handle(key) }
    controller.handleTrigger(revision: tap.session.inputRevision)
    #expect(reader.readCount == 1)
    #expect(tap.session.typed == "xx")
    #expect(writer.calls.isEmpty)
}

@MainActor
@Test func cancelRewriteWhenInputArrivesDuringFocusCheck() {
    let session = TypingSession()
    let reader = InterruptingReader()
    let transaction = RewriteTransaction(
        snapshot: snapshot(reading(value: "word", caret: 4)),
        session: session, reader: reader, completion: { _ in }
    )
    reader.onFocus = {
        session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "x"))
    }
    #expect(!transaction.canContinue())
}
