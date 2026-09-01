import AppKit
import LayoutConversion

/// The pair, as two columns of the same layouts: pick one on each side, and
/// the side that already holds a layout greys it out on the other.
final class PairColumnsView: NSView {
    private static let boxInset: CGFloat = 4
    private static let topInset: CGFloat = 2

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
        let height = CGFloat(max(layouts.count, 1)) * rowHeight
            + Self.topInset + pad + Self.boxInset * 2
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
            cols.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset),
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
            let row = LayoutRow(
                title: layout.name,
                on: layout.id == selected,
                disabled: layout.id == blocked,
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
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: boxInset),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -boxInset),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: boxInset),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -boxInset),
        ])
        return (box, rows)
    }
}

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
        if disabled { clearHover() }
        refreshLayerColors()
    }
}
