import Testing
@testable import Keyflip

private let typed = "выкатили"

@Suite("What a readback says about blind keystrokes")
struct KeyLandingTests {
    @Test("A field still holding the text is the end of it")
    func acceptsTheTextItAskedFor() {
        #expect(
            KeyLanding.judge(
                field: "\(typed) дальше", wasShowing: "dsrfnbkb", expected: typed, mirror: typed
            ) == .landed
        )
    }

    @Test("Monaco's truncated value is a short read, not missing text")
    func acceptsAValueContainedInWhatWeTyped() {
        #expect(
            KeyLanding.judge(
                field: "катили", wasShowing: "dsrfnbkb", expected: typed, mirror: typed
            ) == .landed
        )
    }

    /// The failure this exists for: Slack kept the eight backspaces and none of
    /// the text that was to replace them.
    @Test("A field emptied by our own erase has lost the words")
    func reportsAnEmptiedFieldAsVanished() {
        #expect(
            KeyLanding.judge(
                field: "\n", wasShowing: "dsrfnbkb", expected: typed, mirror: typed
            ) == .vanished
        )
    }

    /// Terminals report no value at all, before the rewrite and after it.
    @Test("A field that never showed a value cannot report losing one")
    func staysQuietWhereTheFieldNeverReads() {
        #expect(
            KeyLanding.judge(
                field: "", wasShowing: "", expected: typed, mirror: typed
            ) == .landed
        )
    }

    /// A mouse click or a Return empties the mirror, and with it any claim that
    /// the empty field is our doing.
    @Test("An empty field the mirror no longer vouches for is only logged")
    func willNotRetypeOnceTheMirrorIsGone() {
        #expect(
            KeyLanding.judge(
                field: "", wasShowing: "dsrfnbkb", expected: typed, mirror: ""
            ) == .disagrees
        )
    }

    @Test("A field holding other text is a disagreement, not a loss")
    func reportsUnrelatedTextAsDisagreement() {
        #expect(
            KeyLanding.judge(
                field: "что-то ещё", wasShowing: "dsrfnbkb", expected: typed, mirror: typed
            ) == .disagrees
        )
    }
}
