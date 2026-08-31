import AppKit
import ApplicationServices
import Foundation

@MainActor
enum Permissions {
    private static var promptedForThisLapse = false

    /// Whether *this running binary* is on the Accessibility TCC list. Do not
    /// probe AX instead: reading our own menu succeeds without trust, which hid
    /// the grant item while field reads returned apiDisabled.
    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var bundlePath: String {
        Bundle.main.bundlePath
    }

    /// ADR 0004: the prompt is not one-shot. Without Accessibility nothing
    /// works, so ask rather than fail forever in silence. The system dialog
    /// carries its own "Open System Settings" button, so do not also yank the
    /// pane forward.
    ///
    /// A lapse arms it, not a launch. Rebuilding the ad-hoc-signed bundle
    /// revokes the grant of the *running* app, and the tap it created while
    /// trusted keeps delivering triggers, so the first failure can land hours
    /// after the launch prompt was spent — and every trigger after it would be
    /// silent. What the API just did is the signal, not `AXIsProcessTrusted()`:
    /// that is a second opinion on the question, and not the one that failed.
    static func promptIfAccessibilityLapsed(available: Bool) {
        guard !available else {
            promptedForThisLapse = false
            return
        }
        guard !promptedForThisLapse else { return }
        promptedForThisLapse = true
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
