import ApplicationServices
import Foundation
import LayoutConversion

@MainActor
final class ConvertController {
    let settings: SettingsStore
    let tap: EventTap
    private var maps: [String: LayoutMap] = [:]
    private var layoutObserver: AnyObject?
    /// Apps whose Accessibility writes were proven not to land. Seeded from
    /// settings at launch, because the first trigger in an app that refuses is
    /// the one that cannot be made to work (ADR 0007) — so it is worth only
    /// paying it once, ever, rather than once per launch.
    private var axWriteRefused: Set<String> = []
    /// A rewrite is posted but not yet settled; a second trigger now would
    /// interleave with it.
    private var rewriteInFlight = false

    /// Long enough to outlast a busy app's main thread, short enough that a
    /// genuine refusal still feels immediate.
    private static let confirmAttempts = 5
    private static let confirmInterval: TimeInterval = 0.03

    /// Synthesized keystrokes are posted to the session tap and applied on the
    /// app's own run loop, so `KeyboardOutput.replace` returning true says
    /// nothing about what is on screen yet.
    private static let keySettle: TimeInterval = 0.2

    /// Monaco answers through a refused write's element with a truncated
    /// value and recovers on its own, but not quickly — 250ms was not enough
    /// and the next trigger, 1.8s later, read the field perfectly. So poll
    /// rather than guess a single delay. Paid on the failure path only, and
    /// now only the first time an app is ever seen to refuse.
    private static let recoverDelay: TimeInterval = 0.15
    private static let recoverAttempts = 10

    init(settings: SettingsStore, tap: EventTap) {
        self.settings = settings
        self.tap = tap
    }

    func start() {
        axWriteRefused = settings.axWriteRefused
        reloadMaps()
        layoutObserver = InputSources.observeEnabledChanges { [weak self] in
            DispatchQueue.main.async { self?.reloadMaps() }
        }
        tap.onTrigger = { [weak self] in
            Task { @MainActor in self?.handleTrigger() }
        }
        tap.start()
        DebugLog.event(
            "start tap=\(tap.isActive) accessibility=\(AXIsProcessTrusted()) " +
            "path=\(Permissions.bundlePath) " +
            "pair=\(settings.slotA ?? "nil")/\(settings.slotB ?? "nil") " +
            "trigger=\(settings.trigger.glyph) maps=\(maps.count) " +
            "axRefused=\(axWriteRefused.sorted().joined(separator: ",") )"
        )
    }

    func reloadMaps() {
        let enabled = InputSources.enabledKeyboardLayouts()
        settings.seedIfNeeded(layouts: enabled)
        var next: [String: LayoutMap] = [:]
        for info in enabled {
            next[info.id] = InputSources.map(for: info)
        }
        // A slot can point at a source the user has since disabled. Keep it
        // usable rather than silently dropping half the pair.
        for id in [settings.slotA, settings.slotB].compactMap({ $0 }) where next[id] == nil {
            next[id] = InputSources.layout(id: id).flatMap(InputSources.map(for:))
        }
        maps = next
    }

    func handleTrigger() {
        guard !rewriteInFlight else {
            DebugLog.event("ignored: previous rewrite still settling")
            return
        }
        guard let pair = settings.pairIDs(), let slotA = maps[pair.0], let slotB = maps[pair.1] else {
            DebugLog.event("abort: pair not ready (\(settings.slotA ?? "nil")/\(settings.slotB ?? "nil"))")
            return
        }

        switch FieldAccess.read() {
        case .noFocus:
            // Nothing focused is not an AX failure, it is the plainest "no
            // target" there is: the trigger still toggles the pair.
            DebugLog.event("field: no focus → toggle")
            togglePair()
        case .unavailable:
            // ADR 0004: a permission failure neither converts nor follows —
            // but it is the one failure worth nagging about.
            DebugLog.event("field: accessibility unavailable → silent")
            Permissions.promptOnceThisLaunch()
        case .markedText, .secure:
            // In-flight IME composition and secure input are designed to fail.
            DebugLog.event("field: blocked → silent")
        case .field(let snap):
            DebugLog.event(
                "field: app=\(snap.app) role=\(snap.role) value=\(DebugLog.quote(snap.value)) " +
                "sel=\(snap.selectedRange) selected=\(DebugLog.quote(snap.selectedText))"
            )
            if let target = target(in: snap) {
                apply(target, snapshot: snap, slotA: slotA, slotB: slotB)
            } else if let typed = typedTarget() {
                // Terminals and Electron editors hand back an empty AXValue.
                // The typing mirror is the only target left.
                applyTyped(typed, in: snap.app, slotA: slotA, slotB: slotB)
            } else {
                DebugLog.event("no target (session=\(tap.session.isLive)) → toggle")
                togglePair()
            }
        }
    }

    /// A non-empty selection always wins. Otherwise the last run of
    /// non-whitespace, and only while a typing session is live (ADR 0002).
    private func target(in snap: FieldSnapshot) -> (text: String, range: NSRange)? {
        if !snap.selectedText.isEmpty {
            return (snap.selectedText, snap.selectedRange)
        }
        if snap.selectedRange.length > 0 {
            let range = FieldAccess.clamp(snap.selectedRange, in: snap.value)
            if range.length > 0 {
                return ((snap.value as NSString).substring(with: range), range)
            }
        }
        guard tap.session.isLive,
              let word = LastWord.range(
                  in: snap.value,
                  caretUTF16: snap.selectedRange.location,
                  sessionUTF16: sessionExtent()
              )
        else { return nil }
        return ((snap.value as NSString).substring(with: word.nsRange), word.nsRange)
    }

    /// How much of the text in front of the caret this typing session put
    /// there, so a run that started before it does not get converted along
    /// with it (`LastWord.range`).
    ///
    /// `nil` when the mirror was emptied by a key we could not account for.
    /// The session is still live, but where it began is no longer known, and
    /// clipping to a zero-length mirror would refuse every conversion.
    private func sessionExtent() -> Int? {
        let mirror = tap.session.typed as NSString
        return mirror.length > 0 ? mirror.length : nil
    }

    /// Write, then confirm — and give the app time to answer.
    ///
    /// `AXUIElementSetAttributeValue` returning success proves nothing: Monaco
    /// returns success and discards the write, while most apps apply it a few
    /// frames later on their own main thread. Reading back immediately called
    /// those apps refusals and retyped over a write that was still in flight,
    /// which is what produced doubled and interleaved text.
    private func rewrite(
        _ target: (text: String, range: NSRange),
        to output: String,
        in snapshot: FieldSnapshot,
        then done: @escaping (Bool) -> Void
    ) {
        // A selection the user made needs nothing mutated through
        // Accessibility: the field already holds the range, and typing
        // replaces it. Take that first.
        //
        // The write is what cannot be undone. Where an app discards it,
        // Monaco being the case in hand, it also fragments the element's
        // accessibility tree — the field reports one half of the run, then
        // the other, and never the selection — so the keystroke fallback has
        // nothing left to work from and the trigger is lost. Waiting does not
        // help: there is no single element to recover. Not writing does.
        if snapshot.selectedText == target.text,
           typeOverSelection(target, as: output, in: snapshot)
        {
            done(true)
            return
        }

        if axWriteRefused.contains(snapshot.app) {
            DebugLog.event("ax write known-refused in \(snapshot.app) → retype")
            done(retype(target, as: output, in: snapshot))
            return
        }
        guard FieldAccess.replace(snapshot, range: target.range, with: output) else {
            DebugLog.event("replace ok=false → retype")
            noteRefusal(snapshot.app)
            retypeAfterFailedWrite(target, as: output, in: snapshot, then: done)
            return
        }
        rewriteInFlight = true
        confirm(target, output: output, in: snapshot, attempt: 0, then: done)
    }

    private func confirm(
        _ target: (text: String, range: NSRange),
        output: String,
        in snapshot: FieldSnapshot,
        attempt: Int,
        then done: @escaping (Bool) -> Void
    ) {
        let check = FieldAccess.verify(
            snapshot,
            range: target.range,
            wrote: output,
            over: target.text
        )
        switch check {
        case .applied:
            DebugLog.event("replace confirmed after \(attempt) recheck(s)")
            rewriteInFlight = false
            done(true)
        case .unreadable:
            // The field will not read back. Assume the write landed rather
            // than retype over it — doubling is worse than not converting.
            DebugLog.event("replace unverifiable after \(attempt) recheck(s); assuming applied")
            rewriteInFlight = false
            done(true)
        case .unchanged where attempt < Self.confirmAttempts:
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmInterval) { [weak self] in
                self?.confirm(target, output: output, in: snapshot, attempt: attempt + 1, then: done)
            }
        case .mangled where attempt < Self.confirmAttempts:
            // Give it the same grace as `.unchanged`: an app part-way through
            // applying the write reads back as neither text for a frame or two.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmInterval) { [weak self] in
                self?.confirm(target, output: output, in: snapshot, attempt: attempt + 1, then: done)
            }
        case .mangled(let value):
            // The write neither applied nor was refused. That is worth acting
            // on, but it is not proof of damage: Monaco's `AXValue` truncates
            // to the trailing token under exactly these conditions, so a field
            // still holding the right text reads back looking wrecked.
            //
            // Giving up here cost a good conversion every time that happened.
            // Hand it to the keystroke path instead, which is safe against
            // both readings — `select` types over the target only once the
            // field confirms the original is still there and selected, and
            // backs out when it cannot.
            DebugLog.event(
                "replace neither applied nor refused after \(attempt) recheck(s): " +
                "\(DebugLog.quote(value)) → retype"
            )
            noteRefusal(snapshot.app)
            rewriteInFlight = false
            retypeAfterFailedWrite(target, as: output, in: snapshot, then: done)
        case .unchanged:
            DebugLog.event("replace did not land after \(attempt) recheck(s) → retype")
            noteRefusal(snapshot.app)
            // Clear before retyping, not after: the keystroke path opens its
            // own settle window, and clearing afterwards would close it again
            // the moment it was opened.
            rewriteInFlight = false
            retypeAfterFailedWrite(target, as: output, in: snapshot, then: done)
        }
    }

    /// Apps that discard Accessibility writes discard all of them. Remember it
    /// for the launch so the next conversion skips straight to retyping and
    /// never opens the double-apply window again.
    private func noteRefusal(_ app: String) {
        guard app != "?", axWriteRefused.insert(app).inserted else { return }
        settings.axWriteRefused = axWriteRefused
        DebugLog.event("ax writes do not land in \(app); remembered")
    }

    /// Fall back to keystrokes, from a field we have looked at again.
    ///
    /// The element a refused write came back through is not reliable. Monaco
    /// answers through it with a truncated value and will not confirm the
    /// selection, so `select` fails all of its attempts and the fallback gives
    /// up — while the next trigger, reading the field from scratch, finds the
    /// same selection intact and rewrites it without trouble. Re-reading is
    /// the whole of that difference.
    ///
    /// It cannot always be done at once. `bestTextElement` keeps the focused
    /// element whenever it reports *any* value, so an immediate re-read hands
    /// back the same truncated node; in the log Monaco was answering properly
    /// again two seconds later. So: try now, and only wait when now is no
    /// good. Apps that hand back a usable field straight away — every app that
    /// is not Monaco — pay nothing for this.
    private func retypeAfterFailedWrite(
        _ target: (text: String, range: NSRange),
        as output: String,
        in snapshot: FieldSnapshot,
        then done: @escaping (Bool) -> Void
    ) {
        retypeAfterFailedWrite(target, as: output, in: snapshot, attempt: 0, then: done)
    }

    private func retypeAfterFailedWrite(
        _ target: (text: String, range: NSRange),
        as output: String,
        in snapshot: FieldSnapshot,
        attempt: Int,
        then done: @escaping (Bool) -> Void
    ) {
        // Log the read itself on the first look and the last, never on the
        // polls between: two lines say what happened, twelve bury it.
        let loud = attempt == 0 || attempt == Self.recoverAttempts
        if let fresh = usable(snapshot, target: target, logging: loud) {
            if attempt > 0 {
                DebugLog.event("field usable again after \(attempt) re-read(s)")
            }
            rewriteInFlight = false
            done(retype(target, as: output, in: fresh))
            return
        }
        guard attempt < Self.recoverAttempts else {
            DebugLog.event("field never became usable after \(attempt) re-read(s)")
            rewriteInFlight = false
            done(retype(target, as: output, in: snapshot))
            return
        }
        rewriteInFlight = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recoverDelay) { [weak self] in
            self?.retypeAfterFailedWrite(
                target, as: output, in: snapshot, attempt: attempt + 1, then: done
            )
        }
    }

    /// A fresh read of the field, or nil when it tells us less than the
    /// snapshot we already hold and so cannot be trusted to type into.
    private func usable(
        _ snapshot: FieldSnapshot,
        target: (text: String, range: NSRange),
        logging: Bool
    ) -> FieldSnapshot? {
        guard case .field(let fresh) = FieldAccess.read() else {
            if logging { DebugLog.event("re-read: no field") }
            return nil
        }
        if logging {
            DebugLog.event(
                "re-read: app=\(fresh.app) value=\(DebugLog.quote(fresh.value)) " +
                "sel=\(fresh.selectedRange) selected=\(DebugLog.quote(fresh.selectedText))"
            )
        }
        guard fresh.app == snapshot.app else { return nil }
        if fresh.selectedText == target.text {
            return fresh
        }
        // No selection to go on, so accept it only while the target is still
        // sitting exactly where we were about to write.
        let value = fresh.value as NSString
        guard target.range.location >= 0,
              target.range.location + target.range.length <= value.length,
              value.substring(with: target.range) == target.text
        else { return nil }
        return fresh
    }

    /// The field read but would not take the write. Two ways out, in order of
    /// how much they assume: select the target through Accessibility and type
    /// over it, or — failing that — backspace over what the mirror says is
    /// there, which needs a caret we can prove is collapsed.
    private func retype(
        _ target: (text: String, range: NSRange),
        as output: String,
        in snapshot: FieldSnapshot
    ) -> Bool {
        if typeOverSelection(target, as: output, in: snapshot) {
            return true
        }
        guard let typed = typedTarget(), typed.text == target.text else {
            DebugLog.event("keys skipped: no selection and no matching mirror")
            return false
        }
        guard FieldAccess.restoreCaret(snapshot) else {
            DebugLog.event("keys skipped: caret not collapsed")
            return false
        }
        let erase = typed.text.count + typed.trailing.count
        let replacement = output + typed.trailing
        guard KeyboardOutput.replace(deleting: erase, with: replacement) else { return false }
        DebugLog.event("replace via keys erase=\(erase) ok=true")
        tap.session.replaceTail(erase, with: replacement)
        settleKeys(expecting: output, in: snapshot.app)
        return true
    }

    /// Put the target under a selection the field agrees with, and type over
    /// it. No range arithmetic and no caret assumptions — the field resolves
    /// the replacement itself.
    private func typeOverSelection(
        _ target: (text: String, range: NSRange),
        as output: String,
        in snapshot: FieldSnapshot
    ) -> Bool {
        guard FieldAccess.select(snapshot, range: target.range, expecting: target.text),
              KeyboardOutput.replace(deleting: 0, with: output)
        else { return false }
        DebugLog.event("replace via selection+keys ok=true")
        syncMirror(after: target.text, became: output)
        settleKeys(expecting: output, in: snapshot.app)
        return true
    }

    /// Keep the trigger closed until synthesized keystrokes have had time to
    /// reach the app, then check what actually landed.
    ///
    /// `rewriteInFlight` used to cover only the Accessibility confirm loop, so
    /// the keystroke paths returned with their events still queued. A second
    /// trigger — and a user who taps again because nothing visibly happened is
    /// the common case — then read the field before those keys arrived,
    /// converted the stale text a second time, and the two rewrites
    /// interleaved: the typed text and the converted text both left behind.
    private func settleKeys(expecting text: String, in app: String) {
        rewriteInFlight = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.keySettle) { [weak self] in
            guard let self else { return }
            self.rewriteInFlight = false
            self.auditKeys(expecting: text, in: app)
        }
    }

    /// The keystroke paths are blind — nothing in them can tell whether the
    /// backspaces and the text both landed. Read the field back once and log
    /// only a disagreement: that line is the whole diagnosis when someone
    /// reports leftover text, and silence keeps the log readable.
    private func auditKeys(expecting text: String, in app: String) {
        guard case .field(let snap) = FieldAccess.read(),
              // Switching app or field in the settle window means this reads
              // somewhere the rewrite never went. Silence beats a false alarm.
              snap.app == app,
              !snap.value.isEmpty,
              !snap.value.contains(text),
              // Monaco answers with the trailing token rather than the whole
              // field. A readback contained *in* what we wrote is a truncated
              // read, not missing text, and saying otherwise cries wolf on
              // every rewrite that worked.
              !text.contains(snap.value)
        else { return }
        DebugLog.event(
            "keys audit: \(DebugLog.quote(text)) not in \(DebugLog.quote(snap.value))"
        )
    }

    /// Keep the mirror usable after a rewrite the mirror did not drive, or drop
    /// it: a mirror that no longer describes the screen is worse than none.
    private func syncMirror(after original: String, became output: String) {
        if let typed = typedTarget(), typed.text == original {
            tap.session.replaceTail(typed.text.count + typed.trailing.count, with: output + typed.trailing)
        } else {
            tap.session.end()
        }
    }

    /// The tail of what we watched the user type: the same "last run of
    /// non-whitespace, trailing space skipped" rule the field path uses, read
    /// from the mirror instead of from the field.
    private func typedTarget() -> (text: String, trailing: String)? {
        let typed = tap.session.typed
        guard tap.session.isLive,
              let word = LastWord.range(in: typed, caretUTF16: (typed as NSString).length)
        else { return nil }
        let ns = typed as NSString
        return (ns.substring(with: word.nsRange), ns.substring(from: word.nsRange.upperBound))
    }

    /// Rewrite blind: backspace over the word (and anything typed after it),
    /// then type the conversion. No Accessibility involved.
    private func applyTyped(
        _ target: (text: String, trailing: String),
        in app: String,
        slotA: LayoutMap,
        slotB: LayoutMap
    ) {
        DebugLog.event("target: typed \(DebugLog.quote(target.text))")
        guard case .rewrite(let conv) = PairConversion.convert(
            target: target.text,
            slotA: slotA,
            slotB: slotB,
            currentSourceID: InputSources.currentID()
        ) else {
            DebugLog.event("convert: noOp \(DebugLog.quote(target.text))")
            return
        }
        DebugLog.event(
            "convert: \(conv.fromSourceID) → \(conv.destinationID) " +
            "\(DebugLog.quote(target.text)) → \(DebugLog.quote(conv.output)) (keys)"
        )
        if conv.output != target.text {
            let erase = target.text.count + target.trailing.count
            let replacement = conv.output + target.trailing
            let ok = KeyboardOutput.replace(deleting: erase, with: replacement)
            DebugLog.event("keys: erase=\(erase) ok=\(ok)")
            guard ok else { return }
            tap.session.replaceTail(erase, with: replacement)
            settleKeys(expecting: conv.output, in: app)
        }
        follow(conv.destinationID)
    }

    private func follow(_ destination: String) {
        DebugLog.event("follow \(destination) ok=\(InputSources.select(destination))")
    }

    /// ADR 0004: a trigger with no target still follows — but only when the
    /// current source is in the pair. Outside the pair it is a plain no-op.
    private func togglePair() {
        guard let pair = settings.pairIDs() else { return }
        let current = [InputSources.currentID(), InputSources.currentLayoutID()].compactMap { $0 }
        let dest: String
        if current.contains(pair.0) {
            dest = pair.1
        } else if current.contains(pair.1) {
            dest = pair.0
        } else {
            DebugLog.event("toggle skipped: \(current) outside pair")
            return
        }
        DebugLog.event("toggle \(current) → \(dest) ok=\(InputSources.select(dest))")
    }

    private func apply(
        _ target: (text: String, range: NSRange),
        snapshot: FieldSnapshot,
        slotA: LayoutMap,
        slotB: LayoutMap
    ) {
        DebugLog.event("target: \(DebugLog.quote(target.text)) range=\(target.range)")
        switch PairConversion.convert(
            target: target.text,
            slotA: slotA,
            slotB: slotB,
            currentSourceID: InputSources.currentID()
        ) {
        case .noOp:
            // A tie with the current source outside the pair. ADR 0001 says
            // the trigger is a no-op — no rewrite and no follow.
            DebugLog.event("convert: noOp \(DebugLog.quote(target.text))")
        case .rewrite(let conv):
            DebugLog.event(
                "convert: \(conv.fromSourceID) → \(conv.destinationID) " +
                "\(DebugLog.quote(target.text)) → \(DebugLog.quote(conv.output))"
            )
            guard conv.output != target.text else {
                // Follow whenever conversion ran, even when no character changed.
                follow(conv.destinationID)
                return
            }
            // Follow only once the rewrite has settled, so the layout does not
            // change 150ms before the text it belongs to.
            rewrite(target, to: conv.output, in: snapshot) { [weak self] rewritten in
                if rewritten {
                    self?.follow(conv.destinationID)
                }
            }
        }
    }

}
