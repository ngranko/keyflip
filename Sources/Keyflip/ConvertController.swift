import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import LayoutConversion

@MainActor
final class ConvertController {
    private let settings: SettingsStore
    private let tap: EventTap
    private let pair: Pair
    private let rewriter: FieldRewriter
    private let reader: FieldReader
    private var waitingForFocus = false

    init(
        settings: SettingsStore,
        tap: EventTap,
        pair: Pair,
        reader: FieldReader,
        rewriter: FieldRewriter
    ) {
        self.settings = settings
        self.tap = tap
        self.pair = pair
        self.reader = reader
        self.rewriter = rewriter
    }

    func start() {
        ElectronAccessibility.prepareFrontmost()
        tap.onTrigger = { [weak self] revision in
            self?.handleTrigger(revision: revision)
        }
        DebugLog.event(
            "start tap=\(tap.modeDescription) accessibility=\(AXIsProcessTrusted()) " +
            "listenEvent=\(CGPreflightListenEventAccess()) " +
            "path=\(Permissions.bundlePath) " +
            "pair=\(pair.slotA ?? "nil")/\(pair.slotB ?? "nil") " +
            "trigger=\(settings.trigger.glyph) maps=\(pair.loadedMapCount) "
        )
    }

    func handleTrigger(revision: UInt64, retryingFocus: Bool = false) {
        guard !waitingForFocus else {
            DebugLog.event("ignored: waiting for accessibility activation")
            return
        }
        guard tap.session.inputRevision == revision else {
            DebugLog.event("cancelled: input changed after trigger")
            return
        }
        guard !rewriter.isSettling else {
            DebugLog.event("ignored: previous rewrite still settling")
            return
        }
        guard let maps = pair.conversionMaps else {
            DebugLog.event("abort: pair not ready (\(pair.slotA ?? "nil")/\(pair.slotB ?? "nil"))")
            return
        }
        let read = reader.read()
        guard tap.session.inputRevision == revision else {
            DebugLog.event("cancelled: input changed during field read")
            return
        }
        Permissions.promptIfAccessibilityLapsed(available: read.accessibilityAvailable)

        switch read {
        case .noFocus:
            if !retryingFocus, waitForAccessibility(revision: revision) { return }
            // Not an AX failure — the plainest "no target" there is.
            DebugLog.event("field: no focus → toggle")
            togglePair()
        case .unavailable:
            tap.session.end(reason: .accessibilityUnavailable)
            // ADR 0004: a permission failure neither converts nor follows.
            DebugLog.event("field: accessibility unavailable → silent")
        case .unsupported:
            tap.session.end(reason: .accessibilityUnavailable)
            DebugLog.event("field exceeds Accessibility budget → skip")
        case .markedText:
            tap.session.end(reason: .markedText)
            DebugLog.event("field: marked text → silent")
        case .secure:
            tap.session.end(reason: .secureInput)
            DebugLog.event("field: secure input → silent")
        case .field(var snap):
            snap.inputRevision = revision
            let reading = snap.reading
            DebugLog.event(
                "field: app=\(reading.app) role=\(reading.role) " +
                "value=\(DebugLog.describeText(reading.value)) " +
                "sel=\(reading.selectedRange) selected=\(DebugLog.describeText(reading.selectedText))"
            )
            convertField(snap, maps: maps)
        }
    }

    private func waitForAccessibility(revision: UInt64) -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        let delay = ElectronAccessibility.remainingDelay(for: pid)
        guard delay > 0 else { return false }
        waitingForFocus = true
        DebugLog.event("waiting for accessibility activation pid=\(pid)")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.waitingForFocus = false
            guard self.tap.session.inputRevision == revision,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                DebugLog.event("accessibility activation retry cancelled: input or app changed")
                return
            }
            self.handleTrigger(revision: revision, retryingFocus: true)
        }
        return true
    }

    private func convertField(_ snap: FieldSnapshot, maps: (slotA: LayoutMap, slotB: LayoutMap)) {
        let verdict = TargetSelection.choose(in: snap.reading, session: tap.session, note: log)
        switch verdict {
        case .field(let target):
            DebugLog.event("target: \(DebugLog.describeText(target.text)) range=\(target.range)")
            apply(target.text, maps: maps) { output, done in
                rewriter.rewrite(target, to: output, in: snap, then: done)
            }
        case .mirror(let text, let trailing):
            DebugLog.event("target: typed \(DebugLog.describeText(text))")
            apply(text, maps: maps, via: " (keys)") { output, done in
                rewriter.typeOverMirror((text, trailing), as: output, in: snap, then: done)
            }
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
                "caret disagrees with mirror: field \(DebugLog.describeText(field)) " +
                "vs typed \(DebugLog.describeText(mirror)) → \(keptMirror ? "keys" : "no rewrite")"
            )
        case .fieldHidesStartOfRun(let mirror):
            DebugLog.event("field shows only the tail of \(DebugLog.describeText(mirror)) → keys")
        case .noTarget(let sessionLive):
            DebugLog.event("no target (session=\(sessionLive)) → toggle")
        }
    }

    private func follow(_ destination: String) {
        DebugLog.event("follow \(destination) ok=\(InputSources.select(destination))")
    }

    /// ADR 0004: a trigger with no target still follows — but only when the
    /// current source is in the pair. Outside the pair it is a plain no-op.
    private func togglePair() {
        guard let ids = pair.ids else { return }
        let current = [InputSources.currentID(), InputSources.currentLayoutID()].compactMap { $0 }
        guard let dest = PairFollow.chooseDestination(from: current, in: ids) else {
            DebugLog.event("toggle skipped: \(current) outside pair")
            return
        }
        DebugLog.event("toggle \(current) → \(dest) ok=\(InputSources.select(dest))")
    }

    private func apply(
        _ text: String,
        maps: (slotA: LayoutMap, slotB: LayoutMap),
        via route: String = "",
        rewrite: (String, @escaping (RewriteOutcome) -> Void) -> Void
    ) {
        guard let conv = convert(text, slotA: maps.slotA, slotB: maps.slotB, via: route) else { return }
        guard conv.output != text else {
            follow(conv.destinationID)
            return
        }
        // Changing the layout before the rewrite settles can interrupt its keystrokes.
        rewrite(conv.output) { [weak self] rewritten in
            if rewritten.shouldFollow { self?.follow(conv.destinationID) }
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
        guard let conv = PairConversion.convert(
            target: text,
            slotA: slotA,
            slotB: slotB,
            currentSourceID: InputSources.currentID()
        ) else {
            DebugLog.event("convert: noOp \(DebugLog.describeText(text))")
            return nil
        }
        DebugLog.event(
            "convert: \(conv.fromSourceID) → \(conv.destinationID) " +
            "\(DebugLog.describeText(text)) → \(DebugLog.describeText(conv.output))\(route)"
        )
        return conv
    }
}
