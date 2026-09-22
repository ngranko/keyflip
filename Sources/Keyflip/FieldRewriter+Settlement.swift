import Foundation

@MainActor
extension FieldRewriter {
    /// What the check for lost text did about it — kept apart from what it
    /// found, because a repair the app would not take leaves the user's words
    /// gone, and that is not a rewrite anyone should follow.
    private enum Repair {
        case unnecessary(RewriteOutcome)
        case typed
        case refused
    }

    /// Hold the trigger closed until synthesized keystrokes have reached the
    /// app, and report the rewrite only then. Without the hold, the keystroke
    /// paths returned with their events still queued, and a second trigger — a
    /// user tapping again because nothing visibly happened — converted the
    /// stale text twice. Without the late report, the caller switched the
    /// input source while those same events were still in flight, which is the
    /// one thing that touches the keyboard between the erase and the text
    /// meant to replace it.
    func settleKeys(
        expecting text: String,
        in app: String,
        wasShowing previous: String,
        replacing range: NSRange? = nil,
        allowUnverified: Bool = false,
        then done: @escaping (RewriteOutcome) -> Void
    ) {
        let settleCaretThenComplete: (RewriteOutcome) -> Void = { [weak self] outcome in
            guard let self, outcome == .applied, let range,
                  case .field(let snapshot) = reader.read(), transaction?.owns(snapshot) == true else {
                done(outcome)
                return
            }
            let caret = NSRange(location: range.location + text.utf16.count, length: 0)
            guard snapshot.reading.selectedRange != caret else { done(.applied); return }
            settleCaret(in: snapshot, after: range, text: text, then: done)
        }
        holdTrigger(for: Self.keySettle) { [weak self] in
            guard let self else { return }
            switch restoreIfKeysVanished(expecting: text, in: app, wasShowing: previous, replacing: range, allowUnverified: allowUnverified) {
            case .unnecessary(let outcome):
                settleCaretThenComplete(outcome)
            // The words are gone and the app would not take them back, so the
            // caller must not follow: switching the layout now leaves the user
            // in a foreign source with nothing to show for it.
            case .refused:
                settleCaretThenComplete(.failed)
            // The repair is keystrokes too, and needs the same room to land.
            case .typed:
                holdTrigger(for: Self.keySettle) { [weak self] in
                    guard let self else { return }
                    let check = restoreIfKeysVanished(expecting: text, in: app, wasShowing: previous,
                                                     replacing: range, allowUnverified: allowUnverified, allowRepair: false)
                    if case .unnecessary(let outcome) = check { settleCaretThenComplete(outcome) }
                    else { settleCaretThenComplete(.unknown) }
                }
            }
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
        wasShowing previous: String,
        replacing range: NSRange?,
        allowUnverified: Bool,
        allowRepair: Bool = true
    ) -> Repair {
        // An identical app name does not establish ownership of this field.
        guard case .field(let snap) = reader.read(), transaction?.owns(snap) == true else {
            return .unnecessary(.unknown)
        }
        guard previous.isEmpty || range != nil else { return .unnecessary(.unknown) }
        let value = snap.reading.value
        switch KeyLanding.judge(
            field: value,
            wasShowing: previous,
            expected: text,
            mirror: session.typed,
            replacing: range
        ) {
        case .landed:
            return .unnecessary(.applied)
        case .unverifiable:
            return .unnecessary(allowUnverified && previous.isEmpty ? .posted : .unknown)
        case .disagrees:
            DebugLog.event("keys audit: \(DebugLog.describeText(text)) not in \(DebugLog.describeText(value))")
            return .unnecessary(.unknown)
        case .vanished:
            guard allowRepair else { return .unnecessary(.unknown) }
            guard canContinue(), writer.typeKeys(deleting: 0, with: text) else {
                DebugLog.event("keys vanished from \(app); retyping \(DebugLog.describeText(text)) refused")
                return .refused
            }
            DebugLog.event("keys vanished from \(app) → typed \(DebugLog.describeText(text)) again")
            return .typed
        }
    }

}
