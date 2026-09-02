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
    private enum Rung: String {
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
    var isSettling: Bool { pendingWaits > 0 }

    /// Waits outstanding. Only `holdTrigger` touches it.
    private var pendingWaits = 0

    private let settings: SettingsStore
    private let session: TypingSession
    private let reader: FieldReader
    private let writer: FieldWriter
    private let wait: Wait

    /// Apps whose Accessibility writes were proven not to land (ADR 0007).
    /// Persisted, because the first trigger in an app that refuses is the one
    /// that cannot be made to work — worth paying once ever, not once a launch.
    private var axWriteRefused: Set<String>

    /// Long enough to outlast a busy app's main thread, short enough that a
    /// genuine refusal still feels immediate.
    private static let confirmAttempts = 5
    private static let confirmInterval: TimeInterval = 0.03

    /// Synthesized keystrokes are applied on the app's own run loop, so
    /// `typeKeys` returning true says nothing about the screen.
    private static let keySettle: TimeInterval = 0.2

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
        wait: Wait
    ) {
        self.settings = settings
        self.session = session
        self.reader = reader
        self.writer = writer
        self.wait = wait
        self.axWriteRefused = settings.axWriteRefused
    }

    /// `AXUIElementSetAttributeValue` returning success proves nothing: Monaco
    /// returns success and discards the write, while most apps apply it a few
    /// frames later. Reading back immediately called those apps refusals and
    /// retyped over a write still in flight, doubling the text.
    func rewrite(
        _ target: Target,
        to output: String,
        in snapshot: FieldSnapshot,
        then done: @escaping (Bool) -> Void
    ) {
        if snapshot.reading.selectedText == target.text,
           typeOverSelection(target, as: output, in: snapshot, via: .userSelection, then: done)
        {
            return
        }
        guard !axWriteRefused.contains(snapshot.reading.app) else {
            DebugLog.event("ax write known-refused in \(snapshot.reading.app) → retype")
            retype(target, as: output, in: snapshot, then: done)
            return
        }
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
        in app: String,
        then done: @escaping (Bool) -> Void
    ) {
        let erase = target.text.count + target.trailing.count
        let replacement = output + target.trailing
        let ok = writer.typeKeys(deleting: erase, with: replacement)
        DebugLog.event("\(Rung.blindKeys.rawValue): erase=\(erase) ok=\(ok)")
        guard ok else {
            done(false)
            return
        }
        session.replaceTail(erase, with: replacement)
        // This is the path for fields that never report a value, so there is
        // no before-and-after to read a loss out of.
        settleKeys(expecting: output, in: app, wasShowing: "", then: done)
    }

    private func confirm(
        _ target: Target,
        output: String,
        in snapshot: FieldSnapshot,
        attempt: Int,
        then done: @escaping (Bool) -> Void
    ) {
        let check = writer.verify(
            snapshot,
            range: target.range,
            wrote: output,
            over: target.text
        )
        switch check {
        case .applied:
            DebugLog.event(
                "replace via \(Rung.accessibilityWrite.rawValue) confirmed " +
                "after \(attempt) recheck(s)"
            )
            done(true)
        case .unreadable:
            // Assume it landed: doubling is worse than not converting.
            DebugLog.event("replace unverifiable after \(attempt) recheck(s); assuming applied")
            done(true)
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
                "\(DebugLog.quote(value)) → retype"
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
        then done: @escaping (Bool) -> Void
    ) {
        noteRefusal(snapshot.reading.app)
        retypeWhenFieldRecovers(target, as: output, in: snapshot, then: done)
    }

    /// Apps that discard Accessibility writes discard all of them, so the next
    /// conversion can skip straight to retyping.
    private func noteRefusal(_ app: String) {
        guard app != "?", axWriteRefused.insert(app).inserted else { return }
        settings.axWriteRefused = axWriteRefused
        DebugLog.event("ax writes do not land in \(app); remembered")
    }

    /// Fall back to keystrokes, from a field read again from scratch: the
    /// element a refused write came back through is not reliable, and Monaco
    /// answers through it with a truncated value it recovers from a moment
    /// later. Re-reading cannot always be done at once, since `bestTextElement`
    /// keeps the focused element whenever it reports any value.
    private func retypeWhenFieldRecovers(
        _ target: Target,
        as output: String,
        in snapshot: FieldSnapshot,
        attempt: Int = 0,
        then done: @escaping (Bool) -> Void
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
            retype(target, as: output, in: snapshot, then: done)
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
                "re-read: app=\(fresh.app) value=\(DebugLog.quote(fresh.value)) " +
                "sel=\(fresh.selectedRange) selected=\(DebugLog.quote(fresh.selectedText))"
            )
        }
        guard fresh.app == snapshot.reading.app else { return nil }
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

    /// The rungs below a write, for a field that reads but will not take one.
    private func retype(
        _ target: Target,
        as output: String,
        in snapshot: FieldSnapshot,
        then done: @escaping (Bool) -> Void
    ) {
        if typeOverSelection(target, as: output, in: snapshot, via: .ourSelection, then: done)
            || typeBlindFromMirror(target, as: output, in: snapshot, then: done) { return }
        done(false)
    }

    /// Put the target under a selection the field agrees with and type over it:
    /// no range arithmetic and no caret assumptions. The bool says whether this
    /// rung took the rewrite, so the ladder stops here; `done` comes later,
    /// once the keystrokes have settled.
    private func typeOverSelection(
        _ target: Target,
        as output: String,
        in snapshot: FieldSnapshot,
        via rung: Rung,
        then done: @escaping (Bool) -> Void
    ) -> Bool {
        guard writer.select(snapshot, range: target.range, expecting: target.text),
              writer.typeKeys(deleting: 0, with: output)
        else { return false }
        DebugLog.event("replace via \(rung.rawValue) ok=true")
        syncMirror(after: target.text, became: output)
        settleKeys(
            expecting: output,
            in: snapshot.reading.app,
            wasShowing: snapshot.reading.value,
            then: done
        )
        return true
    }

    private func typeBlindFromMirror(
        _ target: Target,
        as output: String,
        in snapshot: FieldSnapshot,
        then done: @escaping (Bool) -> Void
    ) -> Bool {
        guard let typed = session.lastRun, typed.text == target.text else {
            DebugLog.event("keys skipped: no selection and no matching mirror")
            return false
        }
        // Deleting by count against a stale selection would eat the whole run.
        guard writer.restoreCaret(snapshot) else {
            DebugLog.event("keys skipped: caret not collapsed")
            return false
        }
        let erase = typed.text.count + typed.trailing.count
        let replacement = output + typed.trailing
        guard writer.typeKeys(deleting: erase, with: replacement) else { return false }
        DebugLog.event("replace via \(Rung.blindKeys.rawValue) erase=\(erase) ok=true")
        session.replaceTail(erase, with: replacement)
        settleKeys(
            expecting: output,
            in: snapshot.reading.app,
            wasShowing: snapshot.reading.value,
            then: done
        )
        return true
    }

    /// Hold the trigger closed until synthesized keystrokes have reached the
    /// app, and report the rewrite only then. Without the hold, the keystroke
    /// paths returned with their events still queued, and a second trigger — a
    /// user tapping again because nothing visibly happened — converted the
    /// stale text twice. Without the late report, the caller switched the
    /// input source while those same events were still in flight, which is the
    /// one thing that touches the keyboard between the erase and the text
    /// meant to replace it.
    private func settleKeys(
        expecting text: String,
        in app: String,
        wasShowing previous: String,
        then done: @escaping (Bool) -> Void
    ) {
        holdTrigger(for: Self.keySettle) { [weak self] in
            guard let self,
                  restoreIfKeysVanished(expecting: text, in: app, wasShowing: previous)
            else {
                done(true)
                return
            }
            // The repair is keystrokes too, and needs the same room to land.
            holdTrigger(for: Self.keySettle) { done(true) }
        }
    }

    /// Every wait the rewriter takes goes through here, so `isSettling` has one
    /// owner and no caller has to reason about when to clear it.
    private func holdTrigger(for delay: TimeInterval, then work: @escaping () -> Void) {
        pendingWaits += 1
        wait.after(delay) { [weak self] in
            self?.pendingWaits -= 1
            work()
        }
    }

    /// The keystroke paths are blind, so read the field back once and act on
    /// what it says. A disagreement is the whole diagnosis for leftover text.
    /// A field left empty is worse than a diagnosis: the backspaces landed and
    /// the replacement did not, so the trigger cost the user the words they
    /// typed. Put them back — an empty field is the one reading where typing
    /// again cannot double anything.
    private func restoreIfKeysVanished(
        expecting text: String,
        in app: String,
        wasShowing previous: String
    ) -> Bool {
        // A different app means this reads somewhere the rewrite never went.
        guard case .field(let snap) = reader.read(), snap.reading.app == app else { return false }
        let value = snap.reading.value
        switch KeyLanding.judge(
            field: value,
            wasShowing: previous,
            expected: text,
            mirror: session.typed
        ) {
        case .landed:
            return false
        case .disagrees:
            DebugLog.event("keys audit: \(DebugLog.quote(text)) not in \(DebugLog.quote(value))")
            return false
        case .vanished:
            DebugLog.event("keys vanished from \(app) → typing \(DebugLog.quote(text)) again")
            return writer.typeKeys(deleting: 0, with: text)
        }
    }

    /// Keep the mirror in step after a rewrite it did not drive, or drop it: a
    /// mirror that no longer describes the screen is worse than none.
    private func syncMirror(after original: String, became output: String) {
        if let typed = session.lastRun, typed.text == original {
            session.replaceTail(typed.text.count + typed.trailing.count, with: output + typed.trailing)
        } else {
            session.end()
        }
    }
}
