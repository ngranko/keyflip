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
        case disagrees(String)
    }

    /// What the posted keystrokes should have left behind, carried through
    /// every audit of them.
    private struct PostedKeys {
        let text: String
        let app: String
        let previous: String
        let range: NSRange?
        let allowUnverified: Bool
    }

    /// Zen's readback can trail keystrokes past `keySettle`: it still held the
    /// original text while the conversion was on screen, and the follow that
    /// disagreement withheld left the user typing on in the wrong layout.
    private static let auditRechecks = 5
    private static let auditInterval: TimeInterval = 0.1

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
        let keys = PostedKeys(text: text, app: app, previous: previous, range: range, allowUnverified: allowUnverified)
        holdTrigger(for: Self.keySettle) { [weak self] in
            self?.auditKeys(keys, attempt: 0) { [weak self] outcome in
                self?.settleCaret(behind: keys, outcome, then: done)
            }
        }
    }

    private func auditKeys(
        _ keys: PostedKeys,
        attempt: Int,
        allowRepair: Bool = true,
        then complete: @escaping (RewriteOutcome) -> Void
    ) {
        switch restoreIfKeysVanished(keys, allowRepair: allowRepair) {
        case .unnecessary(let outcome):
            complete(outcome)
        // The words are gone and the app would not take them back, so the
        // caller must not follow: switching the layout now leaves the user
        // in a foreign source with nothing to show for it.
        case .refused:
            complete(.failed)
        case .disagrees where attempt < Self.auditRechecks:
            holdTrigger(for: Self.auditInterval) { [weak self] in
                self?.auditKeys(keys, attempt: attempt + 1, allowRepair: allowRepair, then: complete)
            }
        case .disagrees(let value):
            DebugLog.event(
                "keys audit: \(DebugLog.describeText(keys.text)) not in \(DebugLog.describeText(value)) " +
                "after \(attempt) recheck(s)"
            )
            complete(.unknown)
        // The repair is keystrokes too, and needs the same room to land.
        case .typed:
            holdTrigger(for: Self.keySettle) { [weak self] in
                self?.auditKeys(keys, attempt: attempt, allowRepair: false, then: complete)
            }
        }
    }

    private func settleCaret(behind keys: PostedKeys, _ outcome: RewriteOutcome, then done: @escaping (RewriteOutcome) -> Void) {
        guard outcome == .applied, let range = keys.range,
              case .field(let snapshot) = reader.read(), transaction?.owns(snapshot) == true else {
            done(outcome)
            return
        }
        let caret = NSRange(location: range.location + keys.text.utf16.count, length: 0)
        guard snapshot.reading.selectedRange != caret else { done(.applied); return }
        settleCaret(in: snapshot, after: range, text: keys.text, then: done)
    }

    /// The keystroke paths are blind, so read the field back and act on what
    /// it says. A disagreement is the whole diagnosis for leftover text.
    /// A field left empty is worse than a diagnosis: the backspaces landed and
    /// the replacement did not, so the trigger cost the user the words they
    /// typed. Put them back — an empty field is the one reading where typing
    /// again cannot double anything.
    private func restoreIfKeysVanished(_ keys: PostedKeys, allowRepair: Bool) -> Repair {
        // An identical app name does not establish ownership of this field.
        guard case .field(let snap) = reader.read(), transaction?.owns(snap) == true else {
            return .unnecessary(.unknown)
        }
        guard keys.previous.isEmpty || keys.range != nil else { return .unnecessary(.unknown) }
        let value = snap.reading.value
        switch KeyLanding.judge(
            field: value,
            wasShowing: keys.previous,
            expected: keys.text,
            mirror: session.typed,
            replacing: keys.range
        ) {
        case .landed:
            return .unnecessary(.applied)
        case .unverifiable:
            return .unnecessary(keys.allowUnverified && keys.previous.isEmpty ? .posted : .unknown)
        case .disagrees:
            return .disagrees(value)
        case .vanished:
            guard allowRepair else { return .unnecessary(.unknown) }
            guard canContinue(), writer.typeKeys(deleting: 0, with: keys.text) else {
                DebugLog.event("keys vanished from \(keys.app); retyping \(DebugLog.describeText(keys.text)) refused")
                return .refused
            }
            DebugLog.event("keys vanished from \(keys.app) → typed \(DebugLog.describeText(keys.text)) again")
            return .typed
        }
    }
}
