import AppKit
import Testing
@testable import Keyflip

@MainActor
struct MenuControlTests {
    @Test func selectedAndBlockedLayoutsExposeTheirState() {
        var presses = 0
        let row = LayoutRow(title: "English", on: true, disabled: false) { presses += 1 }
        #expect(row.accessibilityRole() == .checkBox)
        #expect(row.accessibilityValue() as? Int == 1)
        #expect(row.accessibilityPerformPress())
        row.set(on: false, disabled: true)
        #expect(row.accessibilityValue() as? Int == 0)
        #expect(!row.isAccessibilityEnabled())
        #expect(!row.accessibilityPerformPress())
        #expect(presses == 1)
    }

    @Test func pillsExposeTheirPurposeAndUpdatedValue() {
        var presses = 0
        let pill = PillButton(title: "Off", subtitle: "Launch at login") { presses += 1 }
        #expect(pill.accessibilityRole() == .button)
        #expect(pill.accessibilityLabel() == "Launch at login")
        pill.setTitle("Approval needed…")
        #expect(pill.accessibilityValue() as? String == "Approval needed…")
        #expect(pill.accessibilityPerformPress())
        #expect(presses == 1)
    }
}
