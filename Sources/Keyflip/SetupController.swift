import AppKit

@MainActor
final class SetupController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private let pair: Pair
    private let tap: EventTap
    private let recordTrigger: () -> Void
    private let status = NSTextField(wrappingLabelWithString: "")
    private let layoutA = NSPopUpButton()
    private let layoutB = NSPopUpButton()
    private let trigger = NSButton()
    private let done = NSButton()
    private let access = NSButton()
    private var timer: Timer?
    private var listedIDs: [String] = []

    init(settings: SettingsStore, pair: Pair, tap: EventTap, recordTrigger: @escaping () -> Void) {
        self.settings = settings
        self.pair = pair
        self.tap = tap
        self.recordTrigger = recordTrigger
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Set up Keyflip"
        window.isReleasedWhenClosed = false
        window.delegate = self
        buildContent(in: window)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        pair.reloadFromSystem()
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        // The practice text is never persisted.
        (window?.contentView?.viewWithTag(100) as? NSTextField)?.stringValue = ""
    }

    private func buildContent(in window: NSWindow) {
        let title = NSTextField(labelWithString: "Fix text typed in the wrong layout")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let privacy = NSTextField(wrappingLabelWithString:
            "Keyflip uses Accessibility to read the focused field and replace text when you trigger a conversion. " +
            "It keeps a short typing buffer in memory. Your text is not saved to logs or sent over the network.")
        configureButtons()
        let sample = NSTextField(string: "")
        sample.tag = 100
        sample.placeholderString = "Type a word in the wrong layout here"
        sample.setAccessibilityLabel("Practice conversion")
        let help = NSTextField(wrappingLabelWithString:
            "Type a word, then use your trigger. To convert older text, select it first. " +
            "Base and Shift characters are supported; Option characters, dead keys, and IMEs are not.")
        let stack = NSStackView(views: [title, privacy, access, status,
                                      label("Your two layouts"), layoutA, layoutB, trigger,
                                      label("Try it"), sample, help, done])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -24),
        ])
        for view in [privacy, status, layoutA, layoutB, sample, help] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func configureButtons() {
        for button in [access, trigger, done] { button.bezelStyle = .rounded; button.target = self }
        access.action = #selector(enableAccess)
        trigger.action = #selector(changeTrigger)
        done.title = "Done"
        done.action = #selector(finishSetup)
        for (index, popup) in [layoutA, layoutB].enumerated() {
            popup.tag = index
            popup.target = self
            popup.action = #selector(chooseLayout(_:))
            popup.setAccessibilityLabel(index == 0 ? "Layout A" : "Layout B")
        }
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func refresh() {
        let readiness = SetupReadiness(trusted: Permissions.accessibilityTrusted,
                                       pairReady: pair.conversionMaps != nil, tapActive: tap.isActive)
        status.stringValue = readiness.message
        done.isEnabled = readiness == .ready
        access.title = readiness == .needsTap ? "Retry keyboard monitoring" : "Open Accessibility settings…"
        trigger.title = "Change trigger… Current: \(settings.trigger.glyph)"
        refreshLayouts()
    }

    private func refreshLayouts() {
        let ids = pair.enabledLayouts.map(\.id)
        if listedIDs != ids || layoutA.numberOfItems == 0 {
            listedIDs = ids
            for popup in [layoutA, layoutB] {
                popup.removeAllItems()
                popup.addItem(withTitle: "Choose a layout…")
                for layout in pair.enabledLayouts {
                    popup.addItem(withTitle: layout.name)
                    popup.lastItem?.representedObject = layout.id
                }
                popup.autoenablesItems = false
            }
        }
        for (popup, selected, blocked) in [(layoutA, pair.slotA, pair.slotB), (layoutB, pair.slotB, pair.slotA)] {
            popup.selectItem(at: 0)
            for item in popup.itemArray {
                guard let id = item.representedObject as? String else { item.isEnabled = false; continue }
                item.isEnabled = id != blocked && pair.supportsLayout(id)
                if id == selected { popup.select(item) }
            }
        }
    }

    @objc private func enableAccess() {
        if Permissions.accessibilityTrusted, !tap.isActive {
            tap.rearm()
            if !tap.start() { UserFeedback.showMonitoringFailure() }
        } else { Permissions.requestFromUser() }
        refresh()
    }

    @objc private func chooseLayout(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        if sender.tag == 0 { pair.chooseSlotA(id) } else { pair.chooseSlotB(id) }
        refresh()
    }

    @objc private func changeTrigger() { recordTrigger() }

    @objc private func finishSetup() {
        refresh()
        guard done.isEnabled else { return }
        settings.setupCompleted = true
        Permissions.mayPromptAutomatically = true
        close()
    }
}
