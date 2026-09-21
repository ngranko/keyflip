import Foundation
import LayoutConversion

@MainActor
extension FieldRewriter {
    func retypeAtConfirmedCaret(
        _ target: Target, as output: String, in snapshot: FieldSnapshot,
        then done: @escaping (RewriteOutcome) -> Void
    ) -> Bool {
        let reading = snapshot.reading
        guard let run = session.lastRun,
              reading.selectedText.isEmpty, reading.selectedRange.length == 0,
              target.range.upperBound == reading.selectedRange.location,
              target.text == run.text || target.text == run.text + run.trailing,
              target.range.location >= 0, target.range.upperBound <= reading.value.utf16.count,
              (reading.value as NSString).substring(with: target.range) == target.text else { return false }
        // No selection has been queued on this path, so there is nothing to
        // wait for before the existing caret and ownership checks run.
        typeBlindFromMirror(target, as: output, in: snapshot, then: done)
        return true
    }

    /// The rungs below a write, for a field that reads but will not take one.
    func retype(
        _ target: Target,
        as output: String,
        in snapshot: FieldSnapshot,
        then done: @escaping (RewriteOutcome) -> Void
    ) {
        guard !typeOverSelection(target, as: output, in: snapshot, via: .ourSelection, then: done) else {
            return
        }
        guard canContinue() else { done(.failed); return }
        // A failed selection readback can still have queued a selection in the
        // editor. Let it land before trusting a collapsed caret for backspaces.
        holdTrigger(for: Self.keySettle) { [weak self] in
            self?.typeBlindFromMirror(target, as: output, in: snapshot, then: done)
        }
    }

    /// Put the target under a selection the field agrees with and type over it:
    /// no range arithmetic and no caret assumptions. The bool says whether this
    /// rung took the rewrite, so the ladder stops here; `done` comes later,
    /// once the keystrokes have settled.
    func typeOverSelection(
        _ target: Target,
        as output: String,
        in snapshot: FieldSnapshot,
        via rung: Rung,
        then done: @escaping (RewriteOutcome) -> Void
    ) -> Bool {
        guard canContinue(),
              writer.select(snapshot, range: target.range, expecting: target.text),
              canContinue(),
              writer.typeKeys(deleting: 0, with: output)
        else { return false }
        DebugLog.event("replace via \(rung.rawValue) ok=true")
        syncMirror(after: target.text, became: output)
        settleKeys(
            expecting: output,
            in: snapshot.reading.app,
            wasShowing: snapshot.reading.value,
            replacing: target.range,
            then: done
        )
        return true
    }

    private func typeBlindFromMirror(
        _ target: Target,
        as output: String,
        in snapshot: FieldSnapshot,
        attempt: Int = 0,
        then done: @escaping (RewriteOutcome) -> Void
    ) {
        guard let typed = session.lastRun,
              target.text == typed.text || target.text == typed.text + typed.trailing else {
            DebugLog.event("keys skipped: no selection and no matching mirror")
            done(.failed)
            return
        }
        // Deleting by count against a stale selection would eat the whole run.
        guard canContinue() else { done(.failed); return }
        let caret = writer.restoreCaret(snapshot, expecting: typed.text + typed.trailing)
        guard caret == .collapsed else {
            recheckCaret(caret, target, as: output, in: snapshot, attempt: attempt, then: done)
            return
        }
        let erase = typed.text.count + typed.trailing.count
        let replacement = target.text == typed.text ? output + typed.trailing : output
        guard canContinue(), writer.typeKeys(deleting: erase, with: replacement) else {
            done(.failed)
            return
        }
        DebugLog.event(
            "replace via \(Rung.blindKeys.rawValue) erase=\(erase) ok=true " +
            "after \(attempt) caret recheck(s)"
        )
        session.replaceTail(erase, with: replacement)
        settleKeys(expecting: output, in: snapshot.reading.app, wasShowing: snapshot.reading.value, replacing: target.range, then: done)
    }

    /// Slack and Zen bridge Accessibility through another process and answer
    /// a read from before the write that preceded it. Here that write is the
    /// selection `select` just set, so the caret readback reports it held for
    /// a few milliseconds after the caret has actually collapsed. Asking again
    /// at once, even three times, stayed inside that window and abandoned the
    /// rewrite; the user's second trigger, a second later, always worked.
    private func recheckCaret(
        _ caret: FieldAccess.CaretRestore,
        _ target: Target,
        as output: String,
        in snapshot: FieldSnapshot,
        attempt: Int,
        then done: @escaping (RewriteOutcome) -> Void
    ) {
        guard attempt < Self.confirmAttempts else {
            let why = String(describing: caret)
            DebugLog.event("keys skipped: \(why) after \(attempt) recheck(s)")
            done(.failed)
            return
        }
        holdTrigger(for: Self.confirmInterval) { [weak self] in
            self?.typeBlindFromMirror(target, as: output, in: snapshot, attempt: attempt + 1, then: done)
        }
    }

}
