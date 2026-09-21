import AppKit

@MainActor
extension StatusItemController {
    func addPairControls(to menu: NSMenu) {
        menu.addItem(Self.header("Pair"))
        if pair.conversionMaps == nil {
            let fix = NSMenuItem(title: "Choose two supported layouts…", action: #selector(showSetup), keyEquivalent: "")
            fix.target = self
            menu.addItem(fix)
        }
        let view = PairColumnsView(
            layouts: pair.enabledLayouts, slotA: pair.slotA, slotB: pair.slotB,
            supported: Set(pair.enabledLayouts.filter { pair.supportsLayout($0.id) }.map(\.id)),
            onPickA: { [weak self] id in self?.pickLayout(id, slot: 0) },
            onPickB: { [weak self] id in self?.pickLayout(id, slot: 1) }
        )
        pairView = view
        menu.addItem(Self.hostControls(view))
    }

    private func pickLayout(_ id: String, slot: Int) {
        guard pair.supportsLayout(id) else { return }
        if slot == 0 { pair.chooseSlotA(id) } else { pair.chooseSlotB(id) }
        refreshPairControls()
    }

    func refreshPairControls() {
        pairView?.apply(slotA: pair.slotA, slotB: pair.slotB)
    }

    func addPillControls(to menu: NSMenu) {
        let view = PillsView(
            triggerGlyph: settings.trigger.glyph, launchOn: LaunchAtLogin.isEnabled,
            onSetTrigger: { [weak self] in self?.setTrigger() },
            onToggleLogin: { [weak self] in self?.toggleLogin() }
        )
        pillsView = view
        refreshLoginControl()
        menu.addItem(Self.hostControls(view))
    }

    func refreshLoginControl() {
        pillsView?.setLaunchOn(LaunchAtLogin.isEnabled, needsApproval: LaunchAtLogin.needsApproval)
    }

    private static func hostControls(_ view: MenuControlsView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = view.acceptsFirstResponder
        return item
    }
}
