import AppKit

/// The two settings that are not the pair: what fires a conversion, and
/// whether Keyflip is there to fire it after a restart.
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

final class PillButton: HoverView {
    private let titleField: NSTextField

    init(title: String, subtitle: String, action: @escaping () -> Void) {
        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 12, weight: .semibold)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        self.titleField = titleField
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 40), action: action)
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
}
