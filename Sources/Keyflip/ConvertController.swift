import ApplicationServices
import Foundation
import LayoutConversion

@MainActor
final class ConvertController {
    let settings: SettingsStore
    let tap: EventTap
    private var maps: [String: LayoutMap] = [:]
    private var layoutObserver: AnyObject?
    /// Apps whose Accessibility writes were proven not to land, this launch.
    private var axWriteRefused: Set<String> = []
    /// A rewrite is posted but not yet settled; a second trigger now would
    /// interleave with it.
    private var rewriteInFlight = false

    /// Long enough to outlast a busy app's main thread, short enough that a
    /// genuine refusal still feels immediate.
    private static let confirmAttempts = 5
    private static let confirmInterval: TimeInterval = 0.03

    init(settings: SettingsStore, tap: EventTap) {
        self.settings = settings
        self.tap = tap
    }

    func start() {
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
            "trigger=\(settings.trigger.glyph) maps=\(maps.count)"
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
                applyTyped(typed, slotA: slotA, slotB: slotB)
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
        if axWriteRefused.contains(snapshot.app) {
            DebugLog.event("ax write known-refused in \(snapshot.app) → retype")
            done(retype(target, as: output, in: snapshot))
            return
        }
        guard FieldAccess.replace(snapshot, range: target.range, with: output) else {
            DebugLog.event("replace ok=false → retype")
            noteRefusal(snapshot.app)
            done(retype(target, as: output, in: snapshot))
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
        case .unknown:
            // The field will not read back. Assume the write landed rather
            // than retype over it — doubling is worse than not converting.
            DebugLog.event("replace unverifiable after \(attempt) recheck(s); assuming applied")
            rewriteInFlight = false
            done(true)
        case .unchanged where attempt < Self.confirmAttempts:
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmInterval) { [weak self] in
                self?.confirm(target, output: output, in: snapshot, attempt: attempt + 1, then: done)
            }
        case .unchanged:
            DebugLog.event("replace did not land after \(attempt) recheck(s) → retype")
            noteRefusal(snapshot.app)
            let rewritten = retype(target, as: output, in: snapshot)
            rewriteInFlight = false
            done(rewritten)
        }
    }

    /// Apps that discard Accessibility writes discard all of them. Remember it
    /// for the launch so the next conversion skips straight to retyping and
    /// never opens the double-apply window again.
    private func noteRefusal(_ app: String) {
        guard app != "?", axWriteRefused.insert(app).inserted else { return }
        DebugLog.event("ax writes do not land in \(app); retyping from now on")
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
        if FieldAccess.select(snapshot, range: target.range, expecting: target.text) {
            guard KeyboardOutput.replace(deleting: 0, with: output) else { return false }
            DebugLog.event("replace via selection+keys ok=true")
            syncMirror(after: target.text, became: output)
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
        return true
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
