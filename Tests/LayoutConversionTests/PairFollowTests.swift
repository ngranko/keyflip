import Testing
@testable import LayoutConversion

private let pair = ("com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin")

@Test func followingFromOneSlotSelectsTheOther() {
    #expect(PairFollow.chooseDestination(from: [pair.0], in: pair) == pair.1)
    #expect(PairFollow.chooseDestination(from: [pair.1], in: pair) == pair.0)
}

/// ADR 0004: outside the pair the trigger is a plain no-op, not a toggle into
/// a layout the user never opted into.
@Test func aSourceOutsideThePairDoesNotToggle() {
    #expect(PairFollow.chooseDestination(from: ["com.apple.keylayout.US"], in: pair) == nil)
}

@Test func nothingSelectedDoesNotToggle() {
    #expect(PairFollow.chooseDestination(from: [], in: pair) == nil)
}

/// The input source and the keyboard layout disagree under an IME, so both are
/// offered. Slot A wins, rather than the answer depending on the order asked.
@Test func bothSlotsReportedPrefersTheFirstSlot() {
    #expect(PairFollow.chooseDestination(from: [pair.0, pair.1], in: pair) == pair.1)
    #expect(PairFollow.chooseDestination(from: [pair.1, pair.0], in: pair) == pair.1)
}
