import AppKit

/// A view whose layer colours survive a light/dark switch.
///
/// `NSColor.cgColor` resolves a dynamic colour *once*, against whatever
/// `NSAppearance.current` happens to be — during menu construction that is
/// left over from the last drawing pass — and the CGColor never changes again.
/// Text re-resolves its own `NSColor`, which is how a switch to light mode
/// left black pills sitting behind black labels.
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
        // The menu's appearance only reaches the view once it has a window.
        refreshLayerColors()
    }
}

/// A themed view that lights up under the pointer and runs an action when
/// clicked — every clickable surface the menu has.
class HoverView: ThemedView {
    /// Read from `applyLayerColors`, which runs again on every crossing.
    private(set) var hovering = false

    /// A row already spoken for by the other slot neither lights up nor
    /// answers a click.
    var acceptsHover: Bool { true }

    private let action: () -> Void
    private var tracking: NSTrackingArea?

    init(frame: NSRect, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    /// For a view that stopped accepting hovers while the pointer was on it.
    final func clearHover() {
        hovering = false
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
        guard acceptsHover else { return }
        hovering = true
        refreshLayerColors()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        refreshLayerColors()
    }

    override func mouseUp(with event: NSEvent) {
        guard acceptsHover else { return }
        action()
    }
}

extension NSColor {
    /// The tint the menu's grouped surfaces share. Not
    /// `controlBackgroundColor`: that is pure white in light mode, which
    /// against the menu's translucent grey looked like a cut-out.
    ///
    /// Read it with the target appearance current — `withAlphaComponent`
    /// resolves the dynamic colour where it is called.
    static var menuSurface: NSColor { NSColor.labelColor.withAlphaComponent(0.05) }
}
