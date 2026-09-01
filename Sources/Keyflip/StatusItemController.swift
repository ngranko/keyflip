import AppKit
import LayoutConversion

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let settings: SettingsStore
    private let convert: ConvertController
    private let tap: EventTap
    private var recordPanel: NSPanel?
    private var pairView: PairColumnsView?
    private var pillsView: PillsView?
    private var menuIsOpen = false

    /// The item's menu bar identity, which has to stay the same forever.
    ///
    /// Without this AppKit invents `Item-0` by creation order — as does every
    /// other app that never set one, ControlCenter included. macOS files the
    /// item's position under that name and so do menu bar managers, so a
    /// shared, reused identity leaves Ice's cached window ID stale:
    /// "Missing bounds rectangle for Keyflip".
    private static let autosaveName = "Keyflip"

    init(settings: SettingsStore, convert: ConvertController, tap: EventTap) {
        self.settings = settings
        self.convert = convert
        self.tap = tap
        Self.adoptLegacyPosition()
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem.autosaveName = Self.autosaveName
        super.init()
        configureButton()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Naming the item changes the key its position lives under, so without
    /// this the icon jumps to the end of the menu bar once, on the first launch
    /// after the fix. Must run before the item is created, which is when AppKit
    /// reads the position back.
    private static func adoptLegacyPosition() {
        let defaults = UserDefaults.standard
        let legacy = "NSStatusItem Preferred Position Item-0"
        let current = "NSStatusItem Preferred Position \(autosaveName)"
        guard defaults.object(forKey: current) == nil,
              let position = defaults.object(forKey: legacy) as? Double
        else { return }
        defaults.set(position, forKey: current)
        defaults.removeObject(forKey: legacy)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Keyflip")
        button.image = image?.withSymbolConfiguration(config)
        button.image?.isTemplate = true
        button.toolTip = "Keyflip"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menuIsOpen { return }
        rebuild(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        tap.session.end()
        cancelRecording()
        convert.reloadMaps()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        addAccessibilityGrant(to: menu)
        addPair(to: menu)
        menu.addItem(.separator())
        addPills(to: menu)
        menu.addItem(.separator())
        addFooter(to: menu)
    }

    /// Only while the grant is missing: the menu is settings, not a status
    /// board (ADR 0003).
    private func addAccessibilityGrant(to menu: NSMenu) {
        guard !Permissions.accessibilityTrusted else { return }
        let grant = NSMenuItem(
            title: "Enable Accessibility…",
            action: #selector(requestAccessibility),
            keyEquivalent: ""
        )
        grant.target = self
        grant.isEnabled = true
        grant.toolTip = Permissions.bundlePath
        menu.addItem(grant)
        menu.addItem(.separator())
    }

    private func addPair(to menu: NSMenu) {
        menu.addItem(Self.header("Pair"))
        let pairView = PairColumnsView(
            layouts: InputSources.enabledKeyboardLayouts(),
            slotA: settings.slotA,
            slotB: settings.slotB,
            onPickA: { [weak self] id in
                self?.settings.setSlotA(id)
                self?.convert.reloadMaps()
                self?.pairView?.apply(slotA: id, slotB: self?.settings.slotB)
            },
            onPickB: { [weak self] id in
                self?.settings.setSlotB(id)
                self?.convert.reloadMaps()
                self?.pairView?.apply(slotA: self?.settings.slotA, slotB: id)
            }
        )
        self.pairView = pairView
        menu.addItem(Self.item(hosting: pairView))
    }

    private func addPills(to menu: NSMenu) {
        let pills = PillsView(
            triggerGlyph: settings.trigger.glyph,
            launchOn: LaunchAtLogin.isEnabled,
            onSetTrigger: { [weak self] in
                self?.statusItem.menu?.cancelTracking()
                DispatchQueue.main.async {
                    self?.beginRecording()
                }
            },
            onToggleLogin: { [weak self] in
                LaunchAtLogin.toggle()
                self?.pillsView?.setLaunchOn(LaunchAtLogin.isEnabled)
            }
        )
        self.pillsView = pills
        menu.addItem(Self.item(hosting: pills))
    }

    private func addFooter(to menu: NSMenu) {
        let log = NSMenuItem(
            title: "Show debug log…",
            action: #selector(showDebugLog),
            keyEquivalent: ""
        )
        log.target = self
        log.isEnabled = true
        menu.addItem(log)

        let quit = NSMenuItem(
            title: "Quit Keyflip",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// A frame for a view: it must not highlight or answer a click of its own.
    private static func item(hosting view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = view
        return item
    }

    private static func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return .sectionHeader(title: title)
        }
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        return header
    }

    @objc private func requestAccessibility() {
        statusItem.menu?.cancelTracking()
        Permissions.requestFromUser()
    }

    @objc private func showDebugLog() {
        statusItem.menu?.cancelTracking()
        DebugLogWindow.show()
    }

    private func beginRecording() {
        cancelRecording()
        // The recorder reads the same tap the trigger does; without it the
        // panel would sit there swallowing nothing.
        guard tap.isActive else {
            Permissions.requestFromUser()
            return
        }
        tap.startRecording(interval: NSEvent.doubleClickInterval) { [weak self] result in
            guard let self else { return }
            switch result {
            case .none:
                break
            case .cancel:
                self.cancelRecording()
            case .captured(let trigger):
                self.settings.trigger = trigger
                self.tap.setTrigger(trigger)
                self.pillsView?.setTriggerGlyph(trigger.glyph)
                self.cancelRecording()
            }
        }
        showRecordPanel()
    }

    private func cancelRecording() {
        tap.stopRecording()
        let panel = recordPanel
        recordPanel = nil
        panel?.delegate = nil
        panel?.close()
    }

    private func showRecordPanel() {
        let panel = RecordPanel.make(anchoredTo: statusItem.button)
        panel.delegate = self
        panel.onCancel = { [weak self] in
            self?.cancelRecording()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        recordPanel = panel
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject? === recordPanel else { return }
        cancelRecording()
    }
}
