import AppKit

class MenuControlsView: NSView {
    private var controls: [HoverView] = []
    private var focused: HoverView?

    override var acceptsFirstResponder: Bool {
        controls.contains { $0.acceptsHover }
    }

    func registerControls(_ controls: [HoverView]) {
        self.controls = controls
        for control in controls {
            control.onHover = { [weak self, weak control] in self?.focus(control) }
            control.onHoverExit = { [weak self, weak control] in
                guard let self, self.focused === control else { return }
                self.focus(nil)
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        if focused?.acceptsHover != true {
            focus(controls.first { $0.acceptsHover })
        }
        return true
    }

    override func resignFirstResponder() -> Bool {
        focus(nil)
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { focus(nil) }
    }

    override func keyDown(with event: NSEvent) {
        // AppKit already moved between menu items for these events. Handling
        // them again would skip the first row of the newly focused section.
        if event.keyCode == 125 || event.keyCode == 126 { return }
        if !handleNavigation(event) { super.keyDown(with: event) }
    }

    func handleNavigation(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 123: _ = moveFocus(forward: false)
        case 124: _ = moveFocus(forward: true)
        case 36, 76, 49: activateFocusedControl()
        default: return false
        }
        return true
    }

    @discardableResult
    func moveFocus(forward: Bool) -> Bool {
        let controls = controls.filter(\.acceptsHover)
        guard !controls.isEmpty else { return false }
        guard let focused, let index = controls.firstIndex(where: { $0 === focused }) else {
            focus(forward ? controls.first : controls.last)
            return true
        }
        let next = index + (forward ? 1 : -1)
        guard controls.indices.contains(next) else { return false }
        focus(controls[next])
        return true
    }

    func activateFocusedControl() {
        guard let focused, focused.acceptsHover else { return }
        _ = focused.accessibilityPerformPress()
    }

    private func focus(_ control: HoverView?) {
        focused?.setKeyboardFocus(false)
        focused = control
        focused?.setKeyboardFocus(true)
    }
}
