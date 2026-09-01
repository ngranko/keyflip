import LayoutConversion
import Testing

@Test func characterKeysStartASession() {
    let session = TypingSession()
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x00, flags: 0))
    #expect(session.isLive)
}

@Test func spaceKeepsALiveSession() {
    let session = TypingSession()
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x00, flags: 0))
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x31, flags: 0))
    #expect(session.isLive)
}

@Test func backspaceKeepsALiveSession() {
    let session = TypingSession()
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x00, flags: 0))
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x33, flags: 0))
    #expect(session.isLive)
}

@Test func clickEndsASession() {
    let session = TypingSession()
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x00, flags: 0))
    session.handle(TapEvent(kind: .mouseDown, keyCode: 0, flags: 0))
    #expect(!session.isLive)
}

@Test func arrowsEndASession() {
    let session = TypingSession()
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x00, flags: 0))
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x7B, flags: 0))
    #expect(!session.isLive)
}

@Test func pasteEndsASession() {
    let session = TypingSession()
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x00, flags: 0))
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x09, flags: 1 << 20))
    #expect(!session.isLive)
}

@Test func backspaceAloneDoesNotStartASession() {
    let session = TypingSession()
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x33, flags: 0))
    #expect(!session.isLive)
}

private func typing(_ characters: String, keyCode: UInt16 = 0x00) -> TapEvent {
    TapEvent(kind: .keyDown, keyCode: keyCode, flags: 0, characters: characters)
}

@Test func typedMirrorsWhatWasTyped() {
    let session = TypingSession()
    for ch in "ghbdtn" {
        session.handle(typing(String(ch)))
    }
    #expect(session.typed == "ghbdtn")
}

@Test func backspaceShortensTheMirror() {
    let session = TypingSession()
    session.handle(typing("a"))
    session.handle(typing("b"))
    session.handle(TapEvent(kind: .keyDown, keyCode: 0x33, flags: 0))
    #expect(session.typed == "a")
    #expect(session.isLive)
}

@Test func endingTheSessionClearsTheMirror() {
    let session = TypingSession()
    session.handle(typing("a"))
    session.handle(TapEvent(kind: .mouseDown, keyCode: 0, flags: 0))
    #expect(session.typed.isEmpty)
}

@Test func aKeyWithNoTextDropsTheMirror() {
    let session = TypingSession()
    session.handle(typing("a"))
    // F5 and friends resolve to private-use scalars, not text.
    session.handle(typing("\u{F708}", keyCode: 0x60))
    #expect(session.typed.isEmpty)
    #expect(session.isLive)
}

@Test func mirrorKeepsTheTrailingSpaceSoTheWordCanBeFound() {
    let session = TypingSession()
    for ch in "ghbdtn " {
        session.handle(typing(String(ch), keyCode: ch == " " ? 0x31 : 0x00))
    }
    #expect(session.typed == "ghbdtn ")
    // The trailing space is what the blind rewrite has to erase along with
    // the word, so the mirror reports both halves apart.
    let run = session.lastRun
    #expect(run?.text == "ghbdtn")
    #expect(run?.trailing == " ")
}

@Test func aMirrorWithNothingToSayOffersNoRun() {
    let session = TypingSession()
    #expect(session.lastRun == nil)

    // Backspace alone never starts a session, so there is still nothing to
    // count a rewrite against.
    session.handle(typing("", keyCode: 0x33))
    #expect(session.lastRun == nil)
}

@Test func replaceTailSwapsTheConvertedWordBackIn() {
    let session = TypingSession()
    for ch in "ghbdtn " {
        session.handle(typing(String(ch), keyCode: ch == " " ? 0x31 : 0x00))
    }
    session.replaceTail(7, with: "привет ")
    #expect(session.typed == "привет ")
}

@Test func replaceTailDropsAMirrorItCannotAccountFor() {
    let session = TypingSession()
    for ch in "ghjgf" {
        session.handle(typing(String(ch), keyCode: 0x00))
    }
    // More erased than the mirror ever held: it was never describing the
    // field, so it must not go on claiming to.
    session.replaceTail(9, with: "пропа")
    #expect(session.typed.isEmpty)
    #expect(!session.isLive)
}
