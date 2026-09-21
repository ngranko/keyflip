import AppKit
import LayoutConversion

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, NSWindowDelegate {
    private let statusItem: NSStatusItem
    let settings: SettingsStore
    let pair: Pair
    private let tap: EventTap
    private var recordPanel: NSPanel?
    private var menuIsOpen = false
    var pairView: PairColumnsView?
    var pillsView: PillsView?
    var onShowSetup: (() -> Void)?

    /// The item's menu bar identity, which has to stay the same forever.
    ///
    /// Without this AppKit invents `Item-0` by creation order — as does every
    /// other app that never set one, ControlCenter included. macOS files the
    /// item's position under that name and so do menu bar managers, so a
    /// shared, reused identity leaves Ice's cached window ID stale:
    /// "Missing bounds rectangle for Keyflip".
    private static let autosaveName = "Keyflip"

    init(settings: SettingsStore, pair: Pair, tap: EventTap) {
        self.settings = settings
        self.pair = pair
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
        pair.reloadFromSystem()
        rebuild(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        menuIsOpen = true
        tap.session.end(reason: .menuOpened)
        cancelRecording()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        menuIsOpen = false
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        addAccessibilityGrant(to: menu)
        addTapRecovery(to: menu)
        addPairControls(to: menu)
        menu.addItem(.separator())
        addPillControls(to: menu)
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

    private func addTapRecovery(to menu: NSMenu) {
        guard !tap.isActive, Permissions.accessibilityTrusted else { return }
        let item = NSMenuItem(title: "Keyflip is inactive — Retry", action: #selector(retryTap), keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        menu.addItem(item)
        menu.addItem(.separator())
    }

    @objc private func retryTap() {
        tap.rearm()
        if !tap.start() {
            DebugLog.event("manual tap retry refused")
            UserFeedback.showMonitoringFailure()
        }
    }

    @objc func setTrigger() {
        statusItem.menu?.cancelTracking()
        DispatchQueue.main.async { [weak self] in self?.beginRecording() }
    }

    @objc func toggleLogin() {
        defer { refreshLoginControl() }
        switch LaunchAtLogin.toggle() {
        case .changed: break
        case .requiresApproval: LaunchAtLogin.openSettings()
        case .failed(let domain, let code):
            DebugLog.event("login item failed domain=\(domain) code=\(code)")
            UserFeedback.show(title: "Could not change launch at login",
                              message: "Move Keyflip to Applications, then try again. You can also check System Settings → General → Login Items. Error: \(domain) \(code).")
        }
    }

    @objc func showSetup() {
        statusItem.menu?.cancelTracking()
        DispatchQueue.main.async { [weak self] in self?.onShowSetup?() }
    }

    @objc private func copyDiagnostics() {
        let report = DiagnosticReport.capture(settings: settings, pair: pair, tap: tap)
        NSPasteboard.general.clearContents()
        if !NSPasteboard.general.setString(report.render(log: DebugLog.snapshot()), forType: .string) {
            UserFeedback.show(title: "Could not copy diagnostics", message: "Try again, or copy the contents of Show debug log instead.")
        }
    }

    private func addFooter(to menu: NSMenu) {
        for (title, action) in [("Set up Keyflip…", #selector(showSetup)), ("Copy diagnostic report", #selector(copyDiagnostics))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
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
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    // A separate action avoids AppKit adding its standard Quit icon and
    // reserving an image column for every item in this section.
    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    static func header(_ title: String) -> NSMenuItem {
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

    func beginRecording() {
        cancelRecording()
        // The recorder reads the same tap the trigger does; without it the
        // panel would sit there swallowing nothing.
        if !tap.isActive {
            if Permissions.accessibilityTrusted { retryTap() } else { Permissions.requestFromUser() }
            guard tap.isActive else { return }
        }
        showRecordPanel()
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

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as AnyObject? === recordPanel else { return }
        cancelRecording()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject? === recordPanel else { return }
        cancelRecording()
    }
}
