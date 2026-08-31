import Foundation
import LayoutConversion
import Testing
@testable import Keyflip

@MainActor
private func rewriter(reading readings: [FieldReading]) -> FieldRewriter {
    let defaults = UserDefaults(suiteName: "KeyflipTests")!
    defaults.removePersistentDomain(forName: "KeyflipTests")
    return FieldRewriter(
        settings: SettingsStore(defaults: defaults),
        session: TypingSession(),
        reader: ScriptedField(showing: readings)
    )
}

/// ADR 0007: the fallback types only into a field it has looked at again, and
/// only when that field still shows the target under a selection.
@MainActor
@Test func aFreshReadStillShowingTheSelectionIsUsable() {
    let before = reading(value: "сщьз", caret: 0, selectionLength: 4, selectedText: "сщьз")
    let target = FieldRewriter.Target(text: "сщьз", range: NSRange(location: 0, length: 4))
    let fresh = rewriter(reading: [before]).usable(snapshot(before), target: target, logging: false)
    #expect(fresh?.reading.selectedText == "сщьз")
}

/// With no selection to go on, the target has to still be sitting exactly
/// where the write was about to land.
@MainActor
@Test func aFreshReadWithTheTargetStillInPlaceIsUsable() {
    let before = reading(value: "one сщьз", caret: 8)
    let target = FieldRewriter.Target(text: "сщьз", range: NSRange(location: 4, length: 4))
    let fresh = rewriter(reading: [before]).usable(snapshot(before), target: target, logging: false)
    #expect(fresh != nil)
}

/// Monaco truncates to the trailing token after a refused write. The target is
/// no longer at the range we were about to write, so the fallback declines
/// rather than typing somewhere it cannot vouch for.
@MainActor
@Test func aTruncatedFreshReadIsNotUsable() {
    let before = reading(value: "one сщьз", caret: 8)
    let truncated = reading(value: "сщ", caret: 2)
    let target = FieldRewriter.Target(text: "сщьз", range: NSRange(location: 4, length: 4))
    let fresh = rewriter(reading: [truncated]).usable(
        snapshot(before), target: target, logging: false
    )
    #expect(fresh == nil)
}

/// Focus moved between the write and the re-read, so this reads somewhere the
/// rewrite never went.
@MainActor
@Test func aFreshReadFromAnotherAppIsNotUsable() {
    let before = reading(app: "Cursor", value: "сщьз", caret: 4)
    let elsewhere = reading(app: "Slack", value: "сщьз", caret: 4)
    let target = FieldRewriter.Target(text: "сщьз", range: NSRange(location: 0, length: 4))
    let fresh = rewriter(reading: [elsewhere]).usable(
        snapshot(before), target: target, logging: false
    )
    #expect(fresh == nil)
}

/// A reading with no field handle was never an app we could ask, so every
/// write against it declines — the case the refusal list must not record.
@Test func writesAgainstAHandlelessReadingDecline() {
    let snap = snapshot(reading(value: "сщьз", caret: 4))
    let range = NSRange(location: 0, length: 4)
    #expect(FieldAccess.replace(snap, range: range, with: "comp") == .declined)
    #expect(!FieldAccess.select(snap, range: range, expecting: "сщьз"))
    #expect(!FieldAccess.restoreCaret(snap))
    if case .unreadable = FieldAccess.verify(snap, range: range, wrote: "comp", over: "сщьз") {
    } else {
        Issue.record("expected .unreadable")
    }
}
