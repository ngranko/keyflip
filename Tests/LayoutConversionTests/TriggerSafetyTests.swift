import LayoutConversion
import Testing

@Test func modifierClickCannotCompleteADoubleTap() {
    let recognizer = TriggerRecognizer(interval: 0.5)
    let down = TapEvent(kind: .flagsChanged, keyCode: 0, flags: ModifierKey.option.flagBit)
    let up = TapEvent(kind: .flagsChanged, keyCode: 0, flags: 0)
    #expect(recognizer.handle(down, at: 0) == .none)
    #expect(recognizer.handle(up, at: 0.05) == .none)
    #expect(recognizer.handle(down, at: 0.1) == .none)
    #expect(recognizer.handle(TapEvent(kind: .mouseDown, keyCode: 0, flags: ModifierKey.option.flagBit), at: 0.15) == .none)
    #expect(recognizer.handle(up, at: 0.2) == .none)
}

@Test func chordFiresOnlyOnceUntilItsKeyIsReleased() {
    let flags = ModifierKey.option.flagBit
    let recognizer = TriggerRecognizer(trigger: .chord(Chord(modifiers: flags, keyCode: 0)), interval: 0.5)
    let down = TapEvent(kind: .keyDown, keyCode: 0, flags: flags)
    #expect(recognizer.handle(down, at: 0) == .fired)
    #expect(recognizer.handle(down, at: 0.5) == .consumed)
    #expect(recognizer.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, isRepeat: true), at: 1) == .consumed)
    #expect(recognizer.handle(TapEvent(kind: .keyUp, keyCode: 0, flags: 0), at: 1.1) == .consumed)
    #expect(recognizer.handle(down, at: 1.2) == .fired)
}

@Test func repeatWithoutAnObservedChordDoesNotFire() {
    let flags = ModifierKey.option.flagBit
    let recognizer = TriggerRecognizer(trigger: .chord(Chord(modifiers: flags, keyCode: 0)), interval: 0.5)
    #expect(recognizer.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: flags, isRepeat: true), at: 0) == .none)
}

@Test func recordingCancelsOnClickAndIgnoresAutorepeat() {
    let recorder = Recorder(interval: 0.5)
    #expect(recorder.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: ModifierKey.option.flagBit, isRepeat: true), at: 0) == .none)
    #expect(recorder.handle(TapEvent(kind: .mouseDown, keyCode: 0, flags: 0), at: 0.1) == .cancel)
}
