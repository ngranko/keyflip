import Foundation
import LayoutConversion
import Testing

private let abcID = "com.apple.keylayout.ABC"
private let rusPCID = "com.apple.keylayout.RussianWin"
private let shift = KeyStroke.shiftMods

/// Live layout lookups, serialised and cached.
///
/// The Text Input Source APIs abort when called from several threads at once,
/// and swift-testing runs these tests in parallel — two concurrent callers got
/// away with it, five did not. The app only ever touches them from the main
/// actor, so the lock belongs here rather than in `InputSources`.
private let liveMapLock = NSLock()
nonisolated(unsafe) private var liveMapCache: [String: LayoutMap?] = [:]

private func liveMap(_ id: String) -> LayoutMap? {
    liveMapLock.withLock {
        if let cached = liveMapCache[id] { return cached }
        let map = InputSources.layout(id: id).flatMap(InputSources.map(for:))
        liveMapCache[id] = map
        return map
    }
}

private func latinCyrillicPair() -> (LayoutMap, LayoutMap) {
    let a = LayoutMap(
        id: "latin",
        name: "Latin",
        reverse: [
            "a": KeyStroke(key: 0, mods: 0),
            "A": KeyStroke(key: 0, mods: shift),
            "?": KeyStroke(key: 44, mods: shift),
            "!": KeyStroke(key: 18, mods: shift),
            "&": KeyStroke(key: 26, mods: shift),
            "1": KeyStroke(key: 18, mods: 0),
        ],
        forward: [
            KeyStroke(key: 0, mods: 0): "a",
            KeyStroke(key: 0, mods: shift): "A",
            KeyStroke(key: 44, mods: shift): "?",
            KeyStroke(key: 18, mods: shift): "!",
            KeyStroke(key: 26, mods: shift): "&",
            KeyStroke(key: 18, mods: 0): "1",
        ]
    )
    let b = LayoutMap(
        id: "cyr",
        name: "Cyr",
        reverse: [
            "ф": KeyStroke(key: 0, mods: 0),
            "Ф": KeyStroke(key: 0, mods: shift),
            ",": KeyStroke(key: 44, mods: 0),
            ".": KeyStroke(key: 47, mods: 0),
            "!": KeyStroke(key: 18, mods: shift),
            "1": KeyStroke(key: 18, mods: 0),
        ],
        forward: [
            KeyStroke(key: 0, mods: 0): "ф",
            KeyStroke(key: 0, mods: shift): "Ф",
            KeyStroke(key: 44, mods: 0): ",",
            KeyStroke(key: 44, mods: shift): ",",
            KeyStroke(key: 18, mods: shift): "!",
            KeyStroke(key: 18, mods: 0): "1",
        ]
    )
    return (a, b)
}

@Test func votesPickFromSourceFromTheText() {
    let (latin, cyr) = latinCyrillicPair()
    let decision = PairConversion.convert(
        target: "ффa",
        slotA: latin,
        slotB: cyr,
        currentSourceID: latin.id
    )
    guard case .rewrite(let conv) = decision else {
        Issue.record("expected rewrite")
        return
    }
    #expect(conv.fromSourceID == cyr.id)
    #expect(conv.destinationID == latin.id)
    #expect(conv.output == "aaa")
}

@Test func tieUsesCurrentSourceWhenItIsInThePair() {
    let (latin, cyr) = latinCyrillicPair()
    let decision = PairConversion.convert(
        target: "11",
        slotA: latin,
        slotB: cyr,
        currentSourceID: latin.id
    )
    guard case .rewrite(let conv) = decision else {
        Issue.record("expected rewrite")
        return
    }
    #expect(conv.fromSourceID == latin.id)
    #expect(conv.destinationID == cyr.id)
    #expect(conv.output == "11")
}

@Test func tieIsNoOpWhenCurrentSourceIsNotInThePair() {
    let (latin, cyr) = latinCyrillicPair()
    let decision = PairConversion.convert(
        target: "11",
        slotA: latin,
        slotB: cyr,
        currentSourceID: "com.apple.keylayout.US"
    )
    #expect(decision == .noOp)
}

@Test func unmappedCharactersStay() {
    let (latin, cyr) = latinCyrillicPair()
    let decision = PairConversion.convert(
        target: "ф👋ф",
        slotA: latin,
        slotB: cyr,
        currentSourceID: nil
    )
    guard case .rewrite(let conv) = decision else {
        Issue.record("expected rewrite")
        return
    }
    #expect(conv.output == "a👋a")
}

@Test func questionMarkRewritesWhenThePhysicalKeyDiffers() {
    let (latin, cyr) = latinCyrillicPair()
    let decision = PairConversion.convert(
        target: "a?",
        slotA: latin,
        slotB: cyr,
        currentSourceID: latin.id
    )
    guard case .rewrite(let conv) = decision else {
        Issue.record("expected rewrite")
        return
    }
    #expect(conv.output == "ф,")
}

@Test func bangStaysWhenBothLayoutsShareTheKey() {
    let (latin, cyr) = latinCyrillicPair()
    let decision = PairConversion.convert(
        target: "a!",
        slotA: latin,
        slotB: cyr,
        currentSourceID: latin.id
    )
    guard case .rewrite(let conv) = decision else {
        Issue.record("expected rewrite")
        return
    }
    #expect(conv.output == "ф!")
}

@Test func optionOnlyCharacterDoesNotEnterTheReverseMap() {
    let (latin, _) = latinCyrillicPair()
    #expect(latin.reverse["&"] != nil)
    #expect(latin.reverse["¶"] == nil)
}

@Test func abcAndRussianPCRewriteTheWalkthroughWord() throws {
    let abc = try #require(liveMap(abcID), "ABC is not installed")
    let rus = try #require(liveMap(rusPCID), "Russian – PC is not installed")
    let decision = PairConversion.convert(
        target: "сщьзкурутышму",
        slotA: abc,
        slotB: rus,
        currentSourceID: abc.id
    )
    guard case .rewrite(let conv) = decision else {
        Issue.record("expected rewrite")
        return
    }
    #expect(conv.fromSourceID == rus.id)
    #expect(conv.destinationID == abc.id)
    #expect(conv.output == "comprehensive")
}

@Test func abcQuestionMarkBecomesCommaOnRussianPC() throws {
    let abc = try #require(liveMap(abcID), "ABC is not installed")
    let rus = try #require(liveMap(rusPCID), "Russian – PC is not installed")
    let decision = PairConversion.convert(
        target: "?",
        slotA: abc,
        slotB: rus,
        currentSourceID: abc.id
    )
    guard case .rewrite(let conv) = decision else {
        Issue.record("expected rewrite")
        return
    }
    #expect(conv.output == ",")
}

@Test func smartApostropheConvertsLikeTheKeyThatProducedIt() throws {
    let abc = try #require(liveMap(abcID), "ABC is not installed")
    let rus = try #require(liveMap(rusPCID), "Russian – PC is not installed")
    // macOS substitutes U+2019 as you type, so the field holds a character
    // that is on no layout. It still came off the '/э key.
    let decision = PairConversion.convert(
        target: "\u{2019}njn",
        slotA: abc,
        slotB: rus,
        currentSourceID: abc.id
    )
    guard case .rewrite(let conv) = decision else {
        Issue.record("expected rewrite")
        return
    }
    #expect(conv.output == "этот")
}

@Test func straightApostropheIsUnaffectedByTheFolding() throws {
    let abc = try #require(liveMap(abcID), "ABC is not installed")
    let rus = try #require(liveMap(rusPCID), "Russian – PC is not installed")
    let decision = PairConversion.convert(
        target: "'njn",
        slotA: abc,
        slotB: rus,
        currentSourceID: abc.id
    )
    guard case .rewrite(let conv) = decision else {
        Issue.record("expected rewrite")
        return
    }
    #expect(conv.output == "этот")
}

@Test func emDashIsLeftAloneRatherThanFoldedOntoTheHyphen() throws {
    let abc = try #require(liveMap(abcID), "ABC is not installed")
    let rus = try #require(liveMap(rusPCID), "Russian – PC is not installed")
    let decision = PairConversion.convert(
        target: "njn \u{2014} vfufp",
        slotA: abc,
        slotB: rus,
        currentSourceID: abc.id
    )
    guard case .rewrite(let conv) = decision else {
        Issue.record("expected rewrite")
        return
    }
    #expect(conv.output == "тот \u{2014} магаз")
}
