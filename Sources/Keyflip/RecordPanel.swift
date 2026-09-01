import AppKit

/// The panel shown while the user presses a new trigger. Floating, key without
/// making the app frontmost, and cancelled by Esc.
final class RecordPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    static func make(anchoredTo button: NSStatusBarButton?) -> RecordPanel {
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
        panel.fillContent()
        panel.setFrameOrigin(origin(near: button, sized: panel.frame.size))
        return panel
    }

    private func fillContent() {
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

        guard let content = contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    /// Anchored to the button only while it is on a screen.
    ///
    /// Ice and Bartender hide an item by parking its window at x ≈ -4000, which
    /// is a perfectly real rectangle: checking for one put the panel off screen
    /// with it, asking for a keystroke where nobody could see it.
    private static func origin(near button: NSStatusBarButton?, sized size: NSSize) -> NSPoint {
        if let button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                return NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 12)
            }
        }
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
    }
}
