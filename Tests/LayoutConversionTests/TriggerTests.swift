import Foundation
import LayoutConversion
import Testing

private let option = ModifierKey.option.flagBit
private let optionCodes = ModifierKey.option.keyCodes
private let interval: TimeInterval = 0.5

private func optionEvent(down: Bool, flags: UInt64? = nil) -> TapEvent {
    TapEvent(
        kind: .flagsChanged,
        keyCode: optionCodes[0],
        flags: flags ?? (down ? option : 0)
    )
}

@Test func doubleTapOptionFiresOnSecondRelease() {
    let rec = TriggerRecognizer(trigger: .doubleTap(.option), interval: interval)
    #expect(rec.handle(optionEvent(down: true), at: 1.0) == .none)
    #expect(rec.handle(optionEvent(down: false), at: 1.05) == .none)
    #expect(rec.handle(optionEvent(down: true), at: 1.2) == .none)
    #expect(rec.handle(optionEvent(down: false), at: 1.25) == .fired)
}

@Test func doubleTapDoesNotFireAfterAChord() {
    let rec = TriggerRecognizer(trigger: .doubleTap(.option), interval: interval)
    #expect(rec.handle(optionEvent(down: true), at: 1.0) == .none)
    let letter = TapEvent(kind: .keyDown, keyCode: 0x0E, flags: option)
    #expect(rec.handle(letter, at: 1.02) == .none)
    #expect(rec.handle(optionEvent(down: false), at: 1.04) == .none)
    #expect(rec.handle(optionEvent(down: true), at: 1.1) == .none)
    #expect(rec.handle(optionEvent(down: false), at: 1.12) == .none)
}

@Test func lateSecondTapDoesNotFire() {
    let rec = TriggerRecognizer(trigger: .doubleTap(.option), interval: interval)
    #expect(rec.handle(optionEvent(down: true), at: 1.0) == .none)
    #expect(rec.handle(optionEvent(down: false), at: 1.05) == .none)
    #expect(rec.handle(optionEvent(down: true), at: 2.0) == .none)
    #expect(rec.handle(optionEvent(down: false), at: 2.05) == .none)
}

@Test func extraModifierRejectsATap() {
    let rec = TriggerRecognizer(trigger: .doubleTap(.option), interval: interval)
    let shift: UInt64 = 1 << 17
    #expect(rec.handle(optionEvent(down: true, flags: option | shift), at: 1.0) == .none)
    #expect(rec.handle(optionEvent(down: false, flags: shift), at: 1.05) == .none)
}

@Test func doubleTapFiresWhenFlagsChangedHasNoKeyCode() {
    let rec = TriggerRecognizer(trigger: .doubleTap(.option), interval: interval)
    func event(down: Bool) -> TapEvent {
        TapEvent(kind: .flagsChanged, keyCode: 0, flags: down ? option : 0)
    }
    #expect(rec.handle(event(down: true), at: 1.0) == .none)
    #expect(rec.handle(event(down: false), at: 1.05) == .none)
    #expect(rec.handle(event(down: true), at: 1.2) == .none)
    #expect(rec.handle(event(down: false), at: 1.25) == .fired)
}

@Test func duplicateFlagsChangedDoesNotResetATap() {
    let rec = TriggerRecognizer(trigger: .doubleTap(.option), interval: interval)
    #expect(rec.handle(optionEvent(down: true), at: 1.0) == .none)
    #expect(rec.handle(optionEvent(down: true), at: 1.0) == .none)
    #expect(rec.handle(optionEvent(down: false), at: 1.05) == .none)
    #expect(rec.handle(optionEvent(down: false), at: 1.05) == .none)
    #expect(rec.handle(optionEvent(down: true), at: 1.2) == .none)
    #expect(rec.handle(optionEvent(down: false), at: 1.25) == .fired)
}

@Test func capsLockDoesNotRejectADoubleTap() {
    let rec = TriggerRecognizer(trigger: .doubleTap(.option), interval: interval)
    let caps: UInt64 = 1 << 16
    #expect(rec.handle(optionEvent(down: true, flags: option | caps), at: 1.0) == .none)
    #expect(rec.handle(optionEvent(down: false, flags: caps), at: 1.05) == .none)
    #expect(rec.handle(optionEvent(down: true, flags: option | caps), at: 1.2) == .none)
    #expect(rec.handle(optionEvent(down: false, flags: caps), at: 1.25) == .fired)
}

@Test func recorderCapturesDoubleTapOption() {
    let rec = Recorder(interval: interval)
    #expect(rec.handle(optionEvent(down: true), at: 1.0) == .none)
    #expect(rec.handle(optionEvent(down: false), at: 1.05) == .none)
    #expect(rec.handle(optionEvent(down: true), at: 1.2) == .none)
    #expect(rec.handle(optionEvent(down: false), at: 1.25) == .captured(.doubleTap(.option)))
}

@Test func recorderCancelsOnEscape() {
    let rec = Recorder(interval: interval)
    let esc = TapEvent(kind: .keyDown, keyCode: 0x35, flags: 0)
    #expect(rec.handle(esc, at: 1.0) == .cancel)
}

@Test func chordFiresOnMatchingKeyDown() {
    let chord = Chord(modifiers: (1 << 19) | (1 << 18), keyCode: 0x25)
    let rec = TriggerRecognizer(trigger: .chord(chord), interval: interval)
    let event = TapEvent(kind: .keyDown, keyCode: 0x25, flags: (1 << 19) | (1 << 18))
    #expect(rec.handle(event, at: 1.0) == .fired)
}

@Test func chordIgnoresTheWrongKey() {
    let chord = Chord(modifiers: 1 << 19, keyCode: 0x08)
    let rec = TriggerRecognizer(trigger: .chord(chord), interval: interval)
    let event = TapEvent(kind: .keyDown, keyCode: 0x00, flags: 1 << 19)
    #expect(rec.handle(event, at: 1.0) == .none)
}

@Test func recorderCapturesAChord() {
    let rec = Recorder(interval: interval)
    let event = TapEvent(kind: .keyDown, keyCode: 0x25, flags: (1 << 19) | (1 << 20))
    #expect(rec.handle(event, at: 1.0) == .captured(.chord(Chord(modifiers: (1 << 19) | (1 << 20), keyCode: 0x25))))
}

@Test func recorderIgnoresABareModifierPress() {
    let rec = Recorder(interval: interval)
    let event = TapEvent(kind: .keyDown, keyCode: optionCodes[0], flags: option)
    #expect(rec.handle(event, at: 1.0) == .none)
}
