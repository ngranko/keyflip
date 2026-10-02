import LayoutConversion

@MainActor
final class RewriteTransaction {
    private let snapshot: FieldSnapshot
    private let revision: UInt64
    private let session: TypingSession
    private let reader: FieldReader
    private let completion: (RewriteOutcome) -> Void
    private var cancelled = false

    init(snapshot: FieldSnapshot, session: TypingSession, reader: FieldReader, completion: @escaping (RewriteOutcome) -> Void) {
        self.snapshot = snapshot
        self.revision = snapshot.inputRevision ?? session.inputRevision
        self.session = session
        self.reader = reader
        self.completion = completion
    }

    func canContinue() -> Bool {
        guard !cancelled else { return false }
        guard session.inputRevision == revision else { return cancel(reason: "inputChanged") }
        // Input can arrive on the tap thread while the accessibility focus read blocks.
        let focused = reader.isFocused(snapshot)
        guard session.inputRevision == revision else { return cancel(reason: "inputChangedDuringFocusCheck") }
        guard focused else { return cancel(reason: "focusChangedOrUnavailable") }
        return true
    }

    private func cancel(reason: String) -> Bool {
        cancelled = true
        DebugLog.event("rewrite cancelled app=\(snapshot.reading.app) role=\(snapshot.reading.role) " +
                       "reason=\(reason) expectedRevision=\(revision) observedRevision=\(session.inputRevision)")
        return false
    }

    func owns(_ other: FieldSnapshot) -> Bool { snapshot.handle.matches(other.handle) }

    func finish(_ applied: RewriteOutcome) {
        let outcome = canContinue() ? applied : .failed
        DebugLog.event("rewrite outcome=\(outcome)")
        completion(outcome)
    }
}
