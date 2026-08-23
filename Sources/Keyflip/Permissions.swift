import AppKit
import ApplicationServices
import Foundation

@MainActor
enum Permissions {
    private static var promptedThisLaunch = false

    /// Whether *this running binary* is on the Accessibility TCC list.
    /// Do not probe AX here: reading our own menu can succeed without trust,
    /// which hid the grant item while field reads still returned apiDisabled.
    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var bundlePath: String {
        Bundle.main.bundlePath
    }

    /// ADR 0004: the prompt is not one-shot. Without Accessibility the event
    /// tap cannot even be created, so ask once per launch — every launch —
    /// rather than failing forever in silence. The system dialog carries its
    /// own "Open System Settings" button, so do not also yank the pane forward.
    static func promptOnceThisLaunch() {
        guard !accessibilityTrusted, !promptedThisLaunch else { return }
        promptedThisLaunch = true
        prompt()
    }

    /// The menu item. An explicit user action, so put Settings in front of them.
    static func requestFromUser() {
        prompt()
        openAccessibilitySettings()
    }

    private static func prompt() {
        DebugLog.event("ax: prompt trusted=\(accessibilityTrusted) path=\(bundlePath)")
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
