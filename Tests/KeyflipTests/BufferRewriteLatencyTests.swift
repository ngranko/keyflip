import Foundation
import LayoutConversion
import Testing
@testable import Keyflip

@MainActor
@Test(arguments: ["", "  "])
func knownRefusingEditorRewritesBufferBeforeAnyWait(trailing: String) {
    let prefix = "Earlier message при"
    let editor = EditorModel(prefix + "dtn" + trailing)
    editor.acceptsAX = false
    let session = TypingSession()
    session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "dtn" + trailing))
    let refusals = WriteRefusals()
    refusals.noteFailure(editor.current)
    refusals.noteFailure(editor.current)
    let wait = ManualWait()
    let defaults = UserDefaults(suiteName: "KeyflipLatency-\(UUID().uuidString)")!
    let rewriter = FieldRewriter(settings: SettingsStore(defaults: defaults), session: session,
                                 reader: editor, writer: editor, wait: wait, refusals: refusals)
    var outcome: RewriteOutcome?
    rewriter.rewrite(Target(text: "dtn", range: NSRange(location: prefix.utf16.count, length: 3)),
                     to: "вет", in: editor.current) { outcome = $0 }
    #expect(editor.keyWrites == 1)
    #expect(editor.caretMoves == 1)
    #expect(outcome == nil)
    editor.deliver()
    #expect(editor.current.reading.value == prefix + "вет" + trailing)
    wait.advance()
    #expect(outcome == .applied)
    #expect(session.typed == "вет" + trailing)
}
