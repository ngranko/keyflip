import Foundation
import Testing
@testable import Keyflip

/// ADR 0009. The one failure this app must never have again is a tap that
/// swallows the keyboard: whatever else breaks, input keeps flowing.
struct TapHealthTests {
    @Test func aTapThatTimedOutOnceIsPutBack() {
        var health = TapHealth()
        let first = health.survivesTimeout(at: 100)
        #expect(first)
    }

    @Test func aTapThatKeepsTimingOutIsGivenUpOn() {
        var health = TapHealth()
        let survivals = [100.0, 101].map { health.survivesTimeout(at: $0) }
        #expect(survivals == [true, false])
    }

    @Test func timeoutsAnHourApartAreNotTheSameFault() {
        var health = TapHealth()
        let survivals = [100.0, 3_600].map { health.survivesTimeout(at: $0) }
        #expect(survivals == [true, true])
    }

    @Test func aTimeoutAMinuteOnIsPastTheWindow() {
        var health = TapHealth()
        let survivals = [100.0, 160].map { health.survivesTimeout(at: $0) }
        #expect(survivals == [true, true])
    }

    @Test func aTapArmedAfreshStartsWithACleanRecord() {
        var health = TapHealth()
        _ = health.survivesTimeout(at: 100)
        _ = health.survivesTimeout(at: 101)
        health.forget()
        let afterRearm = health.survivesTimeout(at: 102)
        #expect(afterRearm)
    }
}

/// The only symptom of a tap holding input that is visible from outside it.
struct SwallowedInputTests {
    @Test func keysTheSystemCountsAndTheTapNeverSeesAreHeld() {
        #expect(TapHealth.isSwallowingInput(systemIdle: 0.2, tapIdle: 4))
    }

    @Test func aTapSeeingTheKeysTheSystemSeesIsFine() {
        #expect(!TapHealth.isSwallowingInput(systemIdle: 0.2, tapIdle: 0.3))
    }

    @Test func anIdleMachineIsNotEvidenceOfAnything() {
        #expect(!TapHealth.isSwallowingInput(systemIdle: 90, tapIdle: 90))
    }
}
