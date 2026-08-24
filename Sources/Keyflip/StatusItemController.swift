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

    init(settings: SettingsStore, convert: ConvertController, tap: EventTap) {
        self.settings = settings
        self.convert = convert
        self.tap = tap
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
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

        if !Permissions.accessibilityTrusted {
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

        if #available(macOS 14.0, *) {
            menu.addItem(.sectionHeader(title: "Pair"))
        } else {
            let header = NSMenuItem(title: "Pair", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }

        let layouts = InputSources.enabledKeyboardLayouts()
        let pairView = PairColumnsView(
            layouts: layouts,
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
        let pairItem = NSMenuItem()
        pairItem.isEnabled = false
        pairItem.view = pairView
        menu.addItem(pairItem)

        menu.addItem(.separator())

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
        let pillsItem = NSMenuItem()
        pillsItem.isEnabled = false
        pillsItem.view = pills
        menu.addItem(pillsItem)

        menu.addItem(.separator())

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
        let panel = RecordPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 88),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Set trigger"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onCancel = { [weak self] in
            self?.cancelRecording()
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let line = NSTextField(labelWithString: "Press the new trigger.")
        line.font = .systemFont(ofSize: 13, weight: .medium)
        let hint = NSTextField(labelWithString: "Esc cancels.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(line)
        stack.addArrangedSubview(hint)

        panel.contentView?.addSubview(stack)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])
        }

        if let button = statusItem.button {
            let rect = button.window?.convertToScreen(button.convert(button.bounds, to: nil))
            if let rect {
                panel.setFrameOrigin(NSPoint(x: rect.midX - 120, y: rect.minY - 100))
            }
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

final class RecordPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

final class PairColumnsView: NSView {
    private var rowsA: [String: LayoutRow] = [:]
    private var rowsB: [String: LayoutRow] = [:]

    init(
        layouts: [InputSourceInfo],
        slotA: String?,
        slotB: String?,
        onPickA: @escaping (String) -> Void,
        onPickB: @escaping (String) -> Void
    ) {
        let rowHeight: CGFloat = 22
        let width: CGFloat = 300
        let pad: CGFloat = 8
        let height = CGFloat(max(layouts.count, 1)) * rowHeight + pad * 2
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        autoresizingMask = [.width]

        let cols = NSStackView()
        cols.orientation = .horizontal
        cols.distribution = .fillEqually
        cols.spacing = 6
        cols.translatesAutoresizingMaskIntoConstraints = false

        let builtA = Self.column(layouts: layouts, selected: slotA, blocked: slotB, pick: onPickA)
        let builtB = Self.column(layouts: layouts, selected: slotB, blocked: slotA, pick: onPickB)
        rowsA = builtA.rows
        rowsB = builtB.rows
        cols.addArrangedSubview(builtA.view)
        cols.addArrangedSubview(builtB.view)

        addSubview(cols)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            cols.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            cols.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            cols.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            cols.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(slotA: String?, slotB: String?) {
        for (id, row) in rowsA {
            row.set(on: id == slotA, disabled: id == slotB)
        }
        for (id, row) in rowsB {
            row.set(on: id == slotB, disabled: id == slotA)
        }
    }

    private static func column(
        layouts: [InputSourceInfo],
        selected: String?,
        blocked: String?,
        pick: @escaping (String) -> Void
    ) -> (view: NSView, rows: [String: LayoutRow]) {
        let box = ColumnBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.layer?.cornerRadius = 8
        box.refreshLayerColors()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        var rows: [String: LayoutRow] = [:]
        for layout in layouts {
            let disabled = layout.id == blocked
            let on = layout.id == selected
            let row = LayoutRow(
                title: layout.name,
                on: on,
                disabled: disabled,
                action: { pick(layout.id) }
            )
            rows[layout.id] = row
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        if layouts.isEmpty {
            let empty = NSTextField(labelWithString: "No layouts")
            empty.textColor = .secondaryLabelColor
            empty.font = .menuFont(ofSize: 13)
            empty.alignment = .left
            stack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
        ])
        return (box, rows)
    }
}

/// A view whose layer colours survive a light/dark switch.
///
/// `NSColor.cgColor` resolves a dynamic system colour *once*, against whatever
/// `NSAppearance.current` happens to be, and the CGColor it returns never
/// changes again. Two things go wrong with that. During menu construction
/// `NSAppearance.current` is left over from the last drawing pass rather than
/// the appearance this view will render in, so the colour can be wrong the
/// moment it is set; and a later theme switch cannot reach it at all. Text
/// keeps its `NSColor` and re-resolves itself, which is how a switch to light
/// mode left black pills sitting behind black labels.
///
/// So layer colours are set in one place, resolved against the view's own
/// appearance, and re-applied whenever that appearance changes.
class ThemedView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    /// Set every layer colour here and nowhere else. Runs again on each
    /// appearance change, with that appearance current.
    func applyLayerColors() {}

    final func refreshLayerColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [self] in
            applyLayerColors()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshLayerColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The menu's appearance only reaches the view once it has a window,
        // and that is often the first moment it is knowable.
        refreshLayerColors()
    }
}

extension NSColor {
    /// The tint the menu's grouped surfaces share, so the columns and the
    /// pills read as one panel instead of as content dropped onto it.
    ///
    /// `controlBackgroundColor` is the wrong tool here: it is meant for
    /// content behind a window, and in light mode it is pure white, which
    /// against the menu's translucent grey looked like a cut-out.
    ///
    /// Must be read with the target appearance current — `withAlphaComponent`
    /// resolves the dynamic colour at the point it is called.
    static var menuSurface: NSColor { NSColor.labelColor.withAlphaComponent(0.05) }
}

/// The rounded backing behind one column of layouts.
final class ColumnBox: ThemedView {
    override func applyLayerColors() {
        layer?.backgroundColor = NSColor.menuSurface.cgColor
    }
}

final class LayoutRow: ThemedView {
    private let action: () -> Void
    private var disabled: Bool
    private let tick: NSTextField
    private var tracking: NSTrackingArea?
    private var hovering = false

    init(title: String, on: Bool, disabled: Bool, action: @escaping () -> Void) {
        self.action = action
        self.disabled = disabled
        let tick = NSTextField(labelWithString: on ? "✓" : " ")
        tick.font = .menuFont(ofSize: 11)
        tick.alignment = .center
        tick.translatesAutoresizingMaskIntoConstraints = false
        self.tick = tick
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 22))
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 4
        alphaValue = disabled ? 0.4 : 1
        refreshLayerColors()

        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 13)
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tick)
        addSubview(label)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            tick.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            tick.widthAnchor.constraint(equalToConstant: 14),
            tick.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: tick.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func applyLayerColors() {
        // Accent colour is dynamic too — this follows a change of accent in
        // System Settings as well as a change of theme.
        layer?.backgroundColor = hovering && !disabled
            ? NSColor.controlAccentColor.cgColor
            : nil
    }

    func set(on: Bool, disabled: Bool) {
        self.disabled = disabled
        tick.stringValue = on ? "✓" : " "
        alphaValue = disabled ? 0.4 : 1
        if disabled { hovering = false }
        refreshLayerColors()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !disabled else { return }
        hovering = true
        refreshLayerColors()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        refreshLayerColors()
    }

    override func mouseUp(with event: NSEvent) {
        guard !disabled else { return }
        action()
    }
}

final class PillsView: NSView {
    private let login: PillButton
    private let trigger: PillButton

    init(
        triggerGlyph: String,
        launchOn: Bool,
        onSetTrigger: @escaping () -> Void,
        onToggleLogin: @escaping () -> Void
    ) {
        login = PillButton(
            title: launchOn ? "On" : "Off",
            subtitle: "Launch at login",
            action: onToggleLogin
        )
        trigger = PillButton(
            title: triggerGlyph,
            subtitle: "Set trigger…",
            action: onSetTrigger
        )
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 48))
        autoresizingMask = [.width]
        let row = NSStackView(views: [trigger, login])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setLaunchOn(_ on: Bool) {
        login.setTitle(on ? "On" : "Off")
    }

    func setTriggerGlyph(_ glyph: String) {
        trigger.setTitle(glyph)
    }
}

final class PillButton: ThemedView {
    private let action: () -> Void
    private let titleField: NSTextField
    private var tracking: NSTrackingArea?
    private var hovering = false

    init(title: String, subtitle: String, action: @escaping () -> Void) {
        self.action = action
        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 12, weight: .semibold)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        self.titleField = titleField
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 40))
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        refreshLayerColors()
        let sub = NSTextField(labelWithString: subtitle)
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        sub.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)
        addSubview(sub)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            sub.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            sub.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            sub.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func applyLayerColors() {
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = hovering
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : NSColor.menuSurface.cgColor
    }

    func setTitle(_ title: String) {
        titleField.stringValue = title
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        refreshLayerColors()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        refreshLayerColors()
    }

    override func mouseUp(with event: NSEvent) {
        action()
    }
}
