import Foundation
import LayoutConversion
import Testing
@testable import Keyflip

/// `target(in:)` composes the three witness rules, and every bug ADRs 0006 to
/// 0008 record was a bug in the composition rather than in a rule.
@MainActor
private func controller(typing mirror: String = "") -> ConvertController {
    let tap = EventTap(trigger: .default, interval: 0.3)
    for character in mirror {
        tap.session.handle(
            TapEvent(kind: .keyDown, keyCode: 0x00, flags: 0, characters: String(character))
        )
    }
    let defaults = UserDefaults(suiteName: "KeyflipTests")!
    defaults.removePersistentDomain(forName: "KeyflipTests")
    return ConvertController(
        settings: SettingsStore(defaults: defaults),
        tap: tap,
        reader: ScriptedField()
    )
}

@MainActor
@Test func aSelectionWinsOutrightOverALiveSession() {
    let verdict = controller(typing: "агдд").target(in: reading(
        value: "привет мир",
        caret: 0,
        selectionLength: 6,
        selectedText: "привет"
    ))
    guard case .found(let target) = verdict else { Issue.record("\(verdict)"); return }
    #expect(target.text == "привет")
}

@MainActor
@Test func aSelectedRangeWithNoTextIsSlicedFromTheValue() {
    let verdict = controller().target(in: reading(
        value: "hello world",
        caret: 6,
        selectionLength: 5
    ))
    guard case .found(let target) = verdict else { Issue.record("\(verdict)"); return }
    #expect(target.text == "world")
}

@MainActor
@Test func aDeadSessionWithNoSelectionAsksTheMirror() {
    let verdict = controller().target(in: reading(value: "hello", caret: 5))
    guard case .askTheMirror = verdict else { Issue.record("\(verdict)"); return }
}

/// ADR 0008, from the log: `focal-length-data-` was already in the field and
/// the session typed `агдд`. The run is one hyphenated token, so without the
/// clip the whole identifier converts and the vote drags it the wrong way.
@MainActor
@Test func theSessionClipsARunItOnlyFinished() {
    let verdict = controller(typing: "агдд").target(in: reading(
        value: "focal-length-data-агдд",
        caret: 22
    ))
    guard case .found(let target) = verdict else { Issue.record("\(verdict)"); return }
    #expect(target.text == "агдд")
    #expect(target.range == NSRange(location: 18, length: 4))
}

/// ADR 0007: Zen reports a caret running behind its own value, so the field
/// and the mirror describe different text. The mirror is not at the end of the
/// field either, so erasing by its count would eat text it never saw.
@MainActor
@Test func aCaretPointingSomewhereElseEntirelyRewritesNothing() {
    let verdict = controller(typing: "xyz").target(in: reading(
        value: "hello world",
        caret: 11
    ))
    guard case .unusable = verdict else { Issue.record("\(verdict)"); return }
}

/// The same disagreement, but the mirror *is* the end of the field: the caret
/// is the liar, and keystrokes use the real one.
@MainActor
@Test func aLyingCaretOverAMirrorAtTheEndFallsToKeys() {
    let verdict = controller(typing: "поле").target(in: reading(
        value: "abcполе",
        caret: 3
    ))
    guard case .askTheMirror = verdict else { Issue.record("\(verdict)"); return }
}

/// ADR 0006: Monaco resyncs mid-word and answers with one `(` where the line
/// reads `Ищщдуфт(`. Both witnesses agree over the character they share, so
/// only the run reaching past the value's start tells them apart.
@MainActor
@Test func aValueHoldingOnlyTheTailOfTheRunFallsToKeys() {
    let verdict = controller(typing: "Ищщдуфт(").target(in: reading(value: "(", caret: 1))
    guard case .askTheMirror = verdict else { Issue.record("\(verdict)"); return }
}
