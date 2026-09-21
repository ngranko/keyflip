import AppKit
import LayoutConversion

/// The pair, as two columns of the same layouts: pick one on each side, and
/// the side that already holds a layout greys it out on the other.
final class PairColumnsView: MenuControlsView {
    private static let boxInset: CGFloat = 4
    private static let topInset: CGFloat = 2

    private let supported: Set<String>
    private var rowsA: [String: LayoutRow] = [:]
    private var rowsB: [String: LayoutRow] = [:]

    init(
        layouts: [InputSourceInfo],
        slotA: String?,
        slotB: String?,
        supported: Set<String>,
        onPickA: @escaping (String) -> Void,
        onPickB: @escaping (String) -> Void
    ) {
        self.supported = supported
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

        let builtA = Self.column(layouts: layouts, selected: slotA, blocked: slotB, supported: supported, slot: "A", pick: onPickA)
        let builtB = Self.column(layouts: layouts, selected: slotB, blocked: slotA, supported: supported, slot: "B", pick: onPickB)
        rowsA = builtA.rows
        rowsB = builtB.rows
        registerControls(layouts.flatMap { [builtA.rows[$0.id], builtB.rows[$0.id]].compactMap { $0 } })
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
            row.set(on: id == slotA, disabled: id == slotB || !supported.contains(id))
        }
        for (id, row) in rowsB {
            row.set(on: id == slotB, disabled: id == slotA || !supported.contains(id))
        }
    }

    private static func column(
        layouts: [InputSourceInfo],
        selected: String?,
        blocked: String?,
        supported: Set<String>,
        slot: String,
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
                disabled: layout.id == blocked || !supported.contains(layout.id),
                action: { pick(layout.id) }
            )
            row.setAccessibilityLabel("Layout \(slot): \(layout.name)")
            row.toolTip = supported.contains(layout.id) ? layout.name : "Unsupported layout: \(layout.name)"
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
