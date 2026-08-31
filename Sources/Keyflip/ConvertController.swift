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
    private let reader: FieldReader

    init(settings: SettingsStore, tap: EventTap, reader: FieldReader) {
        self.settings = settings
        self.tap = tap
        self.reader = reader
        self.rewriter = FieldRewriter(settings: settings, session: tap.session, reader: reader)
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

        let read = reader.read()
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
            let reading = snap.reading
            DebugLog.event(
                "field: app=\(reading.app) role=\(reading.role) " +
                "value=\(DebugLog.quote(reading.value)) " +
                "sel=\(reading.selectedRange) selected=\(DebugLog.quote(reading.selectedText))"
            )
            convertField(snap, slotA: slotA, slotB: slotB)
        }
    }

    private func convertField(_ snap: FieldSnapshot, slotA: LayoutMap, slotB: LayoutMap) {
        let verdict = TargetSelection.choose(in: snap.reading, session: tap.session, note: log)
        switch verdict {
        case .field(let target):
            apply(target, snapshot: snap, slotA: slotA, slotB: slotB)
        case .mirror(let text, let trailing):
            applyTyped(
                (text: text, trailing: trailing),
                in: snap.reading.app,
                slotA: slotA,
                slotB: slotB
            )
        case .none, .unusable:
            togglePair()
        }
    }

    /// The verdict's own account of itself, in the words the log has always
    /// used for it.
    private func log(_ note: TargetNote) {
        switch note {
        case .caretDisagreed(let field, let mirror, let keptMirror):
            DebugLog.event(
                "caret disagrees with mirror: field \(DebugLog.quote(field)) " +
                "vs typed \(DebugLog.quote(mirror)) → \(keptMirror ? "keys" : "no rewrite")"
            )
        case .fieldHidesStartOfRun(let mirror):
            DebugLog.event("field shows only the tail of \(DebugLog.quote(mirror)) → keys")
        case .noTarget(let sessionLive):
            DebugLog.event("no target (session=\(sessionLive)) → toggle")
        }
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
