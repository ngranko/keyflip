import ApplicationServices
import Foundation
import LayoutConversion

@MainActor
final class ConvertController {
    let settings: SettingsStore
    let tap: EventTap
    private var maps: [String: LayoutMap] = [:]
    private var layoutObserver: AnyObject?
    private let rewriter: FieldRewriter

    private typealias Target = FieldRewriter.Target

    init(settings: SettingsStore, tap: EventTap) {
        self.settings = settings
        self.tap = tap
        self.rewriter = FieldRewriter(settings: settings, session: tap.session)
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
            "trigger=\(settings.trigger.glyph) maps=\(maps.count) " +
            "axRefused=\(settings.axWriteRefused.sorted().joined(separator: ",") )"
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
        guard !rewriter.isSettling else {
            DebugLog.event("ignored: previous rewrite still settling")
            return
        }
        guard let pair = settings.pairIDs(), let slotA = maps[pair.0], let slotB = maps[pair.1] else {
            DebugLog.event("abort: pair not ready (\(settings.slotA ?? "nil")/\(settings.slotB ?? "nil"))")
            return
        }

        let read = FieldAccess.read()
        Permissions.promptIfAccessibilityLapsed(available: read.accessibilityAvailable)

        switch read {
        case .noFocus:
            // Not an AX failure — the plainest "no target" there is.
            DebugLog.event("field: no focus → toggle")
            togglePair()
        case .unavailable:
            // ADR 0004: a permission failure neither converts nor follows.
            DebugLog.event("field: accessibility unavailable → silent")
        case .markedText, .secure:
            // In-flight IME composition and secure input are designed to fail.
            DebugLog.event("field: blocked → silent")
        case .field(let snap):
            DebugLog.event(
                "field: app=\(snap.app) role=\(snap.role) value=\(DebugLog.quote(snap.value)) " +
                "sel=\(snap.selectedRange) selected=\(DebugLog.quote(snap.selectedText))"
            )
            convertField(snap, slotA: slotA, slotB: slotB)
        }
    }

    private func convertField(_ snap: FieldSnapshot, slotA: LayoutMap, slotB: LayoutMap) {
        switch target(in: snap) {
        case .found(let target):
            apply(target, snapshot: snap, slotA: slotA, slotB: slotB)
        case .askTheMirror:
            guard let typed = tap.session.lastRun else {
                DebugLog.event("no target (session=\(tap.session.isLive)) → toggle")
                togglePair()
                return
            }
            // Terminals and Electron editors hand back an empty AXValue.
            applyTyped(typed, in: snap.app, slotA: slotA, slotB: slotB)
        case .unusable:
            togglePair()
        }
    }

    /// What the field is good for this trigger.
    private enum FieldTarget {
        /// A range the field and the typing mirror both stand behind.
        case found(Target)
        /// No range from the field; the mirror may still have one.
        case askTheMirror
        /// The two witnesses contradict each other, so neither can say where
        /// the target is and nothing is rewritten.
        case unusable
    }

    /// A non-empty selection always wins. Otherwise the last run of
    /// non-whitespace, and only while a typing session is live (ADR 0002) and
    /// agrees with the field about what is in front of the caret.
    private func target(in snap: FieldSnapshot) -> FieldTarget {
        if !snap.selectedText.isEmpty {
            return .found(Target(text: snap.selectedText, range: snap.selectedRange))
        }
        if snap.selectedRange.length > 0 {
            let range = FieldAccess.clamp(snap.selectedRange, in: snap.value)
            if range.length > 0 {
                return .found(Target(
                    text: (snap.value as NSString).substring(with: range),
                    range: range
                ))
            }
        }
        guard tap.session.isLive else { return .askTheMirror }
        let mirror = tap.session.typed
        if let clash = LastWord.caretDisagreement(
            with: mirror,
            in: snap.value,
            caretUTF16: snap.selectedRange.location
        ) {
            // If the mirror's text is at the end of the field after all, the
            // caret is the liar but keystrokes still land, since they use the
            // real one — so drop ranges and keep the mirror. If it is nowhere in
            // the field, the field transformed what was typed (smart quotes) and
            // erasing by the mirror's count would eat text it never saw.
            let mirrored = snap.value.hasSuffix(mirror)
            DebugLog.event(
                "caret disagrees with mirror: field \(DebugLog.quote(clash.field)) " +
                "vs typed \(DebugLog.quote(clash.mirror)) → \(mirrored ? "keys" : "no rewrite")"
            )
            return mirrored ? .askTheMirror : .unusable
        }
        if LastWord.hidesStartOfRun(
            from: mirror,
            in: snap.value,
            caretUTF16: snap.selectedRange.location
        ) {
            // Converting what the field shows would convert “(” to itself and
            // leave the word behind it (Cursor, 2026-08-27).
            DebugLog.event("field shows only the tail of \(DebugLog.quote(mirror)) → keys")
            return .askTheMirror
        }
        guard let word = LastWord.range(
            in: snap.value,
            caretUTF16: snap.selectedRange.location,
            sessionUTF16: sessionExtent()
        ) else { return .askTheMirror }
        return .found(Target(
            text: (snap.value as NSString).substring(with: word.nsRange),
            range: word.nsRange
        ))
    }

    /// How much of the text in front of the caret this session typed, for
    /// `LastWord.range` to clip to. Nil once the mirror has been emptied by a
    /// key we could not account for: clipping to zero would refuse everything.
    private func sessionExtent() -> Int? {
        let mirror = tap.session.typed as NSString
        return mirror.length > 0 ? mirror.length : nil
    }

    private func applyTyped(
        _ target: (text: String, trailing: String),
        in app: String,
        slotA: LayoutMap,
        slotB: LayoutMap
    ) {
        DebugLog.event("target: typed \(DebugLog.quote(target.text))")
        guard let conv = convert(target.text, slotA: slotA, slotB: slotB, via: " (keys)") else {
            return
        }
        if conv.output != target.text {
            guard rewriter.typeOverMirror(target, as: conv.output, in: app) else { return }
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
        _ target: Target,
        snapshot: FieldSnapshot,
        slotA: LayoutMap,
        slotB: LayoutMap
    ) {
        DebugLog.event("target: \(DebugLog.quote(target.text)) range=\(target.range)")
        guard let conv = convert(target.text, slotA: slotA, slotB: slotB) else { return }
        guard conv.output != target.text else {
            // Follow whenever conversion ran, even when no character changed.
            follow(conv.destinationID)
            return
        }
        // Follow only once the rewrite has settled, so the layout does not
        // change 150ms before the text it belongs to.
        rewriter.rewrite(target, to: conv.output, in: snapshot) { [weak self] rewritten in
            if rewritten {
                self?.follow(conv.destinationID)
            }
        }
    }

    /// The conversion for a run of text, logged the same way wherever the run
    /// came from; `route` names the path, for the log alone. Nil on a tie with
    /// the current source outside the pair — a no-op trigger (ADR 0001).
    private func convert(
        _ text: String,
        slotA: LayoutMap,
        slotB: LayoutMap,
        via route: String = ""
    ) -> Conversion? {
        guard case .rewrite(let conv) = PairConversion.convert(
            target: text,
            slotA: slotA,
            slotB: slotB,
            currentSourceID: InputSources.currentID()
        ) else {
            DebugLog.event("convert: noOp \(DebugLog.quote(text))")
            return nil
        }
        DebugLog.event(
            "convert: \(conv.fromSourceID) → \(conv.destinationID) " +
            "\(DebugLog.quote(text)) → \(DebugLog.quote(conv.output))\(route)"
        )
        return conv
    }
}
