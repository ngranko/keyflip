import ApplicationServices
import Foundation
import LayoutConversion

/// Gets a conversion into the field, whatever the field will allow. Which
/// `Rung` runs is decided by what the app does, never by what it says.
@MainActor
final class FieldRewriter {
    /// How the conversion got in. Declared in the order the rungs are tried:
    /// each assumes more about the app than the one above it, and each is
    /// reached only once the ones above are ruled out.
    enum Rung: String {
        /// The field already holds the range, so nothing is mutated through
        /// Accessibility. Preferred because a write an app discards also
        /// fragments the element tree the lower rungs need.
        case userSelection = "user selection"
        /// A write, confirmed by reading it back. Skipped outright in apps
        /// known to discard writes (ADR 0007).
        case accessibilityWrite = "ax write"
        /// A selection set through Accessibility, typed over.
        case ourSelection = "our selection"
        /// Backspaces counted from the typing mirror. No Accessibility at all.
        case blindKeys = "blind keys"
    }

    /// A rewrite is posted but not yet settled; a second trigger now would
    /// interleave with it.
    var isSettling: Bool { transaction != nil || pendingWaits > 0 }

    var transaction: RewriteTransaction?

    /// Waits outstanding. Only `holdTrigger` touches it.
    private var pendingWaits = 0

    let session: TypingSession
    let reader: FieldReader
    let writer: FieldWriter
    private let wait: Wait

    private let refusals: WriteRefusals

    /// Long enough to outlast a busy app's main thread, short enough that a
    /// genuine refusal still feels immediate.
    static let confirmAttempts = 5
    static let confirmInterval: TimeInterval = 0.03

    /// Synthesized keystrokes are applied on the app's own run loop, so
    /// `typeKeys` returning true says nothing about the screen.
    static let keySettle: TimeInterval = 0.2

    /// Monaco recovers from a refused write on its own, but not quickly: 250ms
    /// was not enough, while the next trigger 1.8s later read the field
    /// perfectly. Poll rather than guess a single delay.
    private static let recoverDelay: TimeInterval = 0.15
    private static let recoverAttempts = 10

    init(
        settings: SettingsStore,
        session: TypingSession,
        reader: FieldReader,
        writer: FieldWriter,
        wait: Wait,
        refusals: WriteRefusals = WriteRefusals()
    ) {
        settings.clearLegacyRefusals()
        self.session = session
        self.reader = reader
        self.writer = writer
        self.wait = wait
        self.refusals = refusals
    }

    /// `AXUIElementSetAttributeValue` returning success proves nothing: Monaco
    /// returns success and discards the write, while most apps apply it a few
    /// frames later. Reading back immediately called those apps refusals and
    /// retyped over a write still in flight, doubling the text.
    func rewrite(
        _ target: Target,
        to output: String,
        in snapshot: FieldSnapshot,
        then completion: @escaping (RewriteOutcome) -> Void
    ) {
        guard begin(in: snapshot, then: completion) else { return }
        let done: (RewriteOutcome) -> Void = { [weak self] applied in self?.finish(applied) }
        let (target, output) = RewriteTarget.includeTrailingSpace(target, output: output, in: snapshot.reading)
        if snapshot.reading.selectedText == target.text,
           typeOverSelection(target, as: output, in: snapshot, via: .userSelection, then: done)
        {
            return
        }
        guard !refusals.shouldSkip(snapshot) else {
            DebugLog.event("ax write known-refused in \(snapshot.reading.app) → retype")
            if retypeAtConfirmedCaret(target, as: output, in: snapshot, then: done) { return }
            retype(target, as: output, in: snapshot, then: done)
            return
        }
        guard canContinue() else { done(.failed); return }
        switch writer.replace(snapshot, range: target.range, with: output) {
        case .wrote:
            confirm(target, output: output, in: snapshot, attempt: 0, then: done)
        case .refused:
            DebugLog.event("replace ok=false → retype")
            fallBackToKeys(target, output: output, in: snapshot, then: done)
        case .declined:
            // The app was never asked, so there is no refusal to remember.
            retypeWhenFieldRecovers(target, as: output, in: snapshot, then: done)
        }
    }

    /// Rewrite blind, from the mirror alone — the only path that reaches a
    /// terminal.
    func typeOverMirror(
        _ target: (text: String, trailing: String),
        as output: String,
        in snapshot: FieldSnapshot,
        then completion: @escaping (RewriteOutcome) -> Void
    ) {
        guard begin(in: snapshot, then: completion) else { return }
        let done: (RewriteOutcome) -> Void = { [weak self] applied in self?.finish(applied) }
        let erase = target.text.count + target.trailing.count
        let replacement = output + target.trailing
        let ok = canContinue() && writer.typeKeys(deleting: erase, with: replacement)
        DebugLog.event("\(Rung.blindKeys.rawValue): erase=\(erase) ok=\(ok)")
        guard ok else {
            done(.failed)
            return
        }
        session.replaceTail(erase, with: replacement)
        let before = snapshot.reading.value
        let original = target.text + target.trailing
        let range = before.hasSuffix(original)
            ? NSRange(location: before.utf16.count - original.utf16.count, length: original.utf16.count) : nil
        settleKeys(expecting: replacement, in: snapshot.reading.app, wasShowing: before,
                   replacing: range, allowUnverified: before.isEmpty, then: done)
    }

    private func confirm(
        _ target: Target,
        output: String,
        in snapshot: FieldSnapshot,
        attempt: Int,
        then done: @escaping (RewriteOutcome) -> Void
    ) {
        let check = writer.verify(
            snapshot,
            range: target.range,
            wrote: output,
            over: target.text
        )
        guard canContinue() else { done(.failed); return }
        switch check {
        case .applied:
            DebugLog.event(
                "replace via \(Rung.accessibilityWrite.rawValue) confirmed " +
                "after \(attempt) recheck(s)"
            )
            refusals.noteSuccess(snapshot)
            syncMirror(after: target.text, became: output)
            settleCaret(in: snapshot, after: target.range, text: output, then: done)
        case .unreadable:
            session.discardMirror()
            DebugLog.event("replace unverifiable; no retry or follow")
            done(.unknown)
        // An app part-way through applying a write reads back as neither text
        // for a frame or two, so `.mangled` gets the same grace as `.unchanged`.
        case .unchanged where attempt < Self.confirmAttempts,
             .mangled where attempt < Self.confirmAttempts:
            holdTrigger(for: Self.confirmInterval) { [weak self] in
                self?.confirm(target, output: output, in: snapshot, attempt: attempt + 1, then: done)
            }
        case .mangled(let value):
            // Not proof of damage: Monaco's `AXValue` truncates to the trailing
            // token under exactly these conditions, so a field still holding the
            // right text reads back looking wrecked. The keystroke path is safe
            // against both readings — `select` types over the target only once
            // the field confirms it is still there.
            DebugLog.event(
                "replace neither applied nor refused after \(attempt) recheck(s): " +
                "\(DebugLog.describeText(value)) → retype"
            )
            fallBackToKeys(target, output: output, in: snapshot, then: done)
        case .unchanged:
            DebugLog.event("replace did not land after \(attempt) recheck(s) → retype")
            fallBackToKeys(target, output: output, in: snapshot, then: done)
        }
    }

    private func fallBackToKeys(
        _ target: Target,
        output: String,
        in snapshot: FieldSnapshot,
        then done: @escaping (RewriteOutcome) -> Void
    ) {
        refusals.noteFailure(snapshot)
        retypeWhenFieldRecovers(target, as: output, in: snapshot, then: done)
    }

    /// Fall back to keystrokes, from a field read again from scratch: the
    /// element a refused write came back through is not reliable, and Monaco
    /// answers through it with a truncated value it recovers from a moment
    /// later. Re-reading cannot always be done at once, while the focused element is still reporting truncated text.
    private func retypeWhenFieldRecovers(
        _ target: Target,
        as output: String,
        in snapshot: FieldSnapshot,
        attempt: Int = 0,
        then done: @escaping (RewriteOutcome) -> Void
    ) {
        // Log the first look and the last, never the polls between.
        let loud = attempt == 0 || attempt == Self.recoverAttempts
        if let fresh = usable(snapshot, target: target, logging: loud) {
            if attempt > 0 {
                DebugLog.event("field usable again after \(attempt) re-read(s)")
            }
            retype(target, as: output, in: fresh, then: done)
            return
        }
        guard attempt < Self.recoverAttempts else {
            DebugLog.event("field never became usable after \(attempt) re-read(s)")
            done(.failed)
            return
        }
        holdTrigger(for: Self.recoverDelay) { [weak self] in
            self?.retypeWhenFieldRecovers(
                target, as: output, in: snapshot, attempt: attempt + 1, then: done
            )
        }
    }

    /// A fresh read of the field, or nil when it tells us less than the
    /// snapshot we already hold and so cannot be trusted to type into.
    func usable(
        _ snapshot: FieldSnapshot,
        target: Target,
        logging: Bool
    ) -> FieldSnapshot? {
        guard case .field(let snap) = reader.read() else {
            if logging { DebugLog.event("re-read: no field") }
            return nil
        }
        let fresh = snap.reading
        if logging {
            DebugLog.event(
                "re-read: app=\(fresh.app) value=\(DebugLog.describeText(fresh.value)) " +
                "sel=\(fresh.selectedRange) selected=\(DebugLog.describeText(fresh.selectedText))"
            )
        }
        guard snap.handle.matches(snapshot.handle) else { return nil }
        if fresh.selectedText == target.text {
            return snap
        }
        // No selection to go on, so accept it only while the target is still
        // sitting exactly where we were about to write.
        let value = fresh.value as NSString
        guard target.range.location >= 0,
              target.range.location + target.range.length <= value.length,
              value.substring(with: target.range) == target.text
        else { return nil }
        return snap
    }

    private func begin(in snapshot: FieldSnapshot, then completion: @escaping (RewriteOutcome) -> Void) -> Bool {
        guard !isSettling else { completion(.failed); return false }
        transaction = RewriteTransaction(snapshot: snapshot, session: session, reader: reader, completion: completion)
        guard canContinue() else { finish(.failed); return false }
        return true
    }

    func canContinue() -> Bool { transaction?.canContinue() == true }

    private func finish(_ applied: RewriteOutcome) {
        if applied == .unknown { session.discardMirror() }
        let current = transaction
        transaction = nil
        current?.finish(applied)
    }

    /// Every wait the rewriter takes goes through here, so `isSettling` has one
    /// owner and no caller has to reason about when to clear it.
    func holdTrigger(for delay: TimeInterval, then work: @escaping () -> Void) {
        pendingWaits += 1
        wait.after(delay) { [weak self] in
            guard let self else { return }
            pendingWaits -= 1
            guard canContinue() else { finish(.failed); return }
            work()
        }
    }

    /// Keep the mirror in step after a rewrite it did not drive, or drop it: a
    /// mirror that no longer describes the screen is worse than none.
    func syncMirror(after original: String, became output: String) {
        if session.typed.hasSuffix(original), !original.isEmpty {
            session.replaceTail(original.count, with: output)
        } else {
            session.discardMirror()
        }
    }
}
