import LayoutConversion
import Testing
import os

@Test func reportUnknownKeyTextWithoutRecordingCharacters() {
    let reports = OSAllocatedUnfairLock(initialState: [SessionReset]())
    let session = TypingSession { report in reports.withLock { $0.append(report) } }
    session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "🙂ab"))
    session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0))
    let report = reports.withLock { $0.first }
    #expect(report?.reason == .emptyKeyText)
    #expect(report?.wasLive == true)
    #expect(report?.mirroredUTF16 == 4)
    #expect(report?.revision == session.inputRevision)
    #expect(!String(describing: report).contains("🙂ab"))
}

@Test func distinguishInputCausesOfSessionReset() {
    let cases: [(TapEvent, SessionResetReason)] = [
        (.init(kind: .mouseDown, keyCode: 0, flags: 0), .mouseDown),
        (.init(kind: .keyDown, keyCode: 0x33, flags: 1 << 19), .modifiedDeletion),
        (.init(kind: .keyDown, keyCode: 0x09, flags: 1 << 20), .shortcut),
        (.init(kind: .keyDown, keyCode: 0x7B, flags: 0), .caretMovement),
        (.init(kind: .keyDown, keyCode: 0x24, flags: 0), .commitOrCancel),
        (.init(kind: .keyDown, keyCode: 0x75, flags: 0), .forwardDelete),
        (.init(kind: .keyDown, keyCode: 0x33, flags: 0), .backspaceExhausted),
        (.init(kind: .keyDown, keyCode: 0x60, flags: 0, characters: "\u{F708}"), .nonTextKey),
    ]
    for (event, reason) in cases {
        let reports = OSAllocatedUnfairLock(initialState: [SessionReset]())
        let session = TypingSession { report in reports.withLock { $0.append(report) } }
        session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "a"))
        session.handle(event)
        #expect(reports.withLock { $0.last?.reason } == reason)
    }
}

@Test func suppressRepeatedEmptyResetsButReportTheNextLiveSession() {
    let reports = OSAllocatedUnfairLock(initialState: [SessionReset]())
    let session = TypingSession { report in reports.withLock { $0.append(report) } }
    session.end(reason: .tapBusy)
    session.end(reason: .tapBusy)
    #expect(reports.withLock { $0.count } == 1)
    session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "a"))
    session.end(reason: .tapBusy)
    #expect(reports.withLock { $0.count } == 2)
    #expect(reports.withLock { $0.last?.wasLive } == true)
}

@Test func reportRewriteInvalidationWithoutChangingInputRevision() {
    let reports = OSAllocatedUnfairLock(initialState: [SessionReset]())
    let session = TypingSession { report in reports.withLock { $0.append(report) } }
    session.handle(TapEvent(kind: .keyDown, keyCode: 0, flags: 0, characters: "a"))
    let revision = session.inputRevision
    session.replaceTail(2, with: "b")
    #expect(reports.withLock { $0.last?.reason } == .mirrorMismatch)
    session.discardMirror()
    #expect(reports.withLock { $0.last?.reason } == .mirrorDiscarded)
    #expect(session.inputRevision == revision)
}

@Test func releaseTheSessionLockBeforeReportingAReset() {
    let reference = OSAllocatedUnfairLock<TypingSession?>(initialState: nil)
    let observed = OSAllocatedUnfairLock(initialState: false)
    let session = TypingSession { _ in
        let current = reference.withLock { $0 }
        observed.withLock { $0 = current?.typed.isEmpty == true }
    }
    reference.withLock { $0 = session }
    session.end(reason: .appActivated)
    #expect(observed.withLock { $0 })
    reference.withLock { $0 = nil }
}
