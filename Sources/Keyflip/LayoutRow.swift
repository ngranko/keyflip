import AppKit

/// The rounded backing behind one column of layouts.
final class ColumnBox: ThemedView {
    override func applyLayerColors() {
        layer?.backgroundColor = NSColor.menuSurface.cgColor
    }
}

final class LayoutRow: HoverView {
    private let tick: NSTextField
    private var disabled: Bool

    override var acceptsHover: Bool { !disabled }

    init(title: String, on: Bool, disabled: Bool, action: @escaping () -> Void) {
        self.disabled = disabled
        let tick = NSTextField(labelWithString: on ? "✓" : " ")
        tick.font = .menuFont(ofSize: 11)
        tick.alignment = .center
        tick.translatesAutoresizingMaskIntoConstraints = false
        self.tick = tick
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 22), action: action)
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 4
        setAccessibilityRole(.checkBox)
        setAccessibilityValue(on ? 1 : 0)
        setAccessibilityEnabled(!disabled)
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
        setAccessibilityRole(.checkBox)
        setAccessibilityValue(on ? 1 : 0)
        setAccessibilityEnabled(!disabled)
        alphaValue = disabled ? 0.4 : 1
        if disabled { clearHover() }
        refreshLayerColors()
    }
}
