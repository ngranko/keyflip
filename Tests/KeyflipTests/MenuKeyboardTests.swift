import AppKit
import Testing
@testable import Keyflip

@MainActor
struct MenuKeyboardTests {
    @Test func navigationSkipsBlockedLayoutsAndActivatesTheFocusedChoice() {
        var selections: [Int] = []
        let controls = (0..<4).map { index in
            LayoutRow(title: "Layout \(index)", on: false, disabled: index == 1) { selections.append(index) }
        }
        let view = MenuControlsView()
        view.registerControls(controls)
        #expect(view.becomeFirstResponder())
        #expect(controls[0].keyboardFocused)
        view.keyDown(with: press(124))
        #expect(controls[2].keyboardFocused)
        view.keyDown(with: press(49))
        view.keyDown(with: press(124))
        view.keyDown(with: press(36))
        #expect(selections == [2, 3])
        view.keyDown(with: press(123))
        #expect(controls[2].keyboardFocused)
    }

    @Test func leavingASectionClearsFocusAndDisabledControlsCannotActivate() {
        var presses = 0
        let row = LayoutRow(title: "Layout", on: false, disabled: false) { presses += 1 }
        let view = MenuControlsView()
        view.registerControls([row])
        #expect(view.becomeFirstResponder())
        row.set(on: false, disabled: true)
        view.activateFocusedControl()
        #expect(presses == 0)
        #expect(!view.acceptsFirstResponder)
        #expect(view.resignFirstResponder())
        #expect(!row.keyboardFocused)
    }

    @Test func menuNavigationAndModifiedKeysRemainWithAppKit() {
        let view = MenuControlsView()
        view.registerControls([HoverView(frame: .zero, action: {})])
        #expect(view.becomeFirstResponder())
        for code: UInt16 in [125, 126, 53] {
            #expect(!view.handleNavigation(press(code)))
        }
        #expect(!view.handleNavigation(press(124, modifiers: .control)))
        #expect(!view.handleNavigation(press(12, modifiers: .command)))
    }

    @Test func mouseExitClearsTheOutlineAndKeyboardNavigationRestoresIt() {
        let control = HoverView(frame: .zero, action: {})
        let view = MenuControlsView()
        view.registerControls([control])
        control.mouseEntered(with: crossBoundary(.mouseEntered))
        #expect(control.keyboardFocused)
        control.mouseExited(with: crossBoundary(.mouseExited))
        #expect(!control.keyboardFocused)
        view.keyDown(with: press(124))
        #expect(control.keyboardFocused)
    }

    @Test func exitingAnOldControlDoesNotClearTheNewFocus() {
        let first = HoverView(frame: .zero, action: {})
        let second = HoverView(frame: .zero, action: {})
        let view = MenuControlsView()
        view.registerControls([first, second])
        first.mouseEntered(with: crossBoundary(.mouseEntered))
        second.mouseEntered(with: crossBoundary(.mouseEntered))
        first.mouseExited(with: crossBoundary(.mouseExited))
        #expect(!first.keyboardFocused)
        #expect(second.keyboardFocused)
    }

    private func crossBoundary(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                              windowNumber: 0, context: nil, eventNumber: 0,
                              trackingNumber: 0, userData: nil)!
    }

    private func press(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                        timestamp: 0, windowNumber: 0, context: nil, characters: "",
                        charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
}
