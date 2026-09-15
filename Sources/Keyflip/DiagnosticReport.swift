import AppKit

struct DiagnosticReport {
    let version: String
    let system: String
    let architecture: String
    let layoutA: String?
    let layoutB: String?
    let trigger: String
    let trusted: Bool
    let tapState: String
    let pairReady: Bool
    let loginState: String

    func render(log: String, homeDirectory: String = NSHomeDirectory()) -> String {
        let report = """
        Keyflip \(version)
        macOS: \(system)
        Process architecture: \(architecture)
        Supported: macOS 13+, Apple Silicon and Intel
        Layout A: \(layoutA ?? "unset")
        Layout B: \(layoutB ?? "unset")
        Trigger: \(trigger)
        Accessibility: \(trusted ? "granted" : "missing")
        Keyboard monitoring: \(tapState)
        Layout pair ready: \(pairReady)
        Launch at login: \(loginState)

        Recent diagnostics, without field contents:
        \(log)
        """
        guard !homeDirectory.isEmpty else { return report }
        return report.replacingOccurrences(of: homeDirectory, with: "~")
    }

    @MainActor
    static func capture(settings: SettingsStore, pair: Pair, tap: EventTap) -> DiagnosticReport {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unversioned"
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return DiagnosticReport(version: "\(version) (\(build))", system: ProcessInfo.processInfo.operatingSystemVersionString,
                                architecture: architecture, layoutA: pair.slotA, layoutB: pair.slotB,
                                trigger: settings.trigger.glyph, trusted: Permissions.accessibilityTrusted,
                                tapState: "\(tap.modeDescription); active=\(tap.isActive); retired=\(tap.isRetired)",
                                pairReady: pair.conversionMaps != nil,
                                loginState: LaunchAtLogin.needsApproval ? "approval needed" : (LaunchAtLogin.isEnabled ? "on" : "off"))
    }
}
