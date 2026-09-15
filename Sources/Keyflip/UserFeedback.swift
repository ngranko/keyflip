import AppKit

@MainActor
enum UserFeedback {
    static func show(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    static func showMonitoringFailure() {
        show(title: "Keyboard monitoring could not start",
             message: "Check that Keyflip is enabled in System Settings → Privacy & Security → Accessibility, then retry. " +
                "If it still fails, restart Keyflip and copy a diagnostic report from its menu.")
    }
}
