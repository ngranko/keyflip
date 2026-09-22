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
        // Input can arrive on the tap thread while the accessibility focus read blocks.
        guard !cancelled, session.inputRevision == revision,
              reader.isFocused(snapshot), session.inputRevision == revision else {
            cancelled = true
            return false
        }
        return true
    }

    func owns(_ other: FieldSnapshot) -> Bool { snapshot.handle.matches(other.handle) }

    func finish(_ applied: RewriteOutcome) {
        let outcome = canContinue() ? applied : .failed
        DebugLog.event("rewrite outcome=\(outcome)")
        completion(outcome)
    }
}
