import Foundation
import LayoutConversion
import Testing
@testable import Keyflip

@MainActor
@Test(arguments: ["", "  "])
func resumedWordSurvivesDelayedSelectionAndRepeatedRewrites(trailing: String) {
    let prefix = "Earlier message при"
    let editor = EditorModel(prefix + "dtn" + trailing)
    editor.acceptsAX = false
    editor.delaysSelection = true
    let session = TypingSession()
    session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: prefix))
    session.end(reason: .appActivated)
    session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "other window"))
    session.end(reason: .appActivated)
    session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "dtn" + trailing))
    let wait = ManualWait()
    let defaults = UserDefaults(suiteName: "KeyflipResumedWord-\(UUID().uuidString)")!
    let rewriter = FieldRewriter(settings: SettingsStore(defaults: defaults), session: session,
                                 reader: editor, writer: editor, wait: wait)

    for output in ["вет", "dtn", "вет"] {
        guard case .field(let target) = TargetSelection.choose(in: editor.current.reading, session: session, note: { _ in }) else {
            Issue.record("The resumed word must remain rewritable")
            return
        }
        #expect(target.range == NSRange(location: prefix.utf16.count, length: 3))
        var result: RewriteOutcome?
        rewriter.rewrite(target, to: output, in: editor.current) { result = $0 }
        for _ in 0..<10 { editor.deliver(); wait.advance() }
        #expect(result == .applied)
        #expect(editor.current.reading.value == prefix + output + trailing)
        #expect(editor.current.reading.selectedRange == NSRange(location: (prefix + output + trailing).utf16.count, length: 0))
        #expect(session.typed == output + trailing)
        #expect(!rewriter.isSettling)
    }
}
