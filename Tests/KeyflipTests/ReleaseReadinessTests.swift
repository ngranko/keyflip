import Foundation
import ServiceManagement
import Testing
@testable import Keyflip

@Test func setupExplainsTheFirstUnmetRequirement() {
    #expect(SetupReadiness(trusted: false, pairReady: false, tapActive: false) == .needsPermission)
    #expect(SetupReadiness(trusted: true, pairReady: false, tapActive: true) == .needsPair)
    #expect(SetupReadiness(trusted: true, pairReady: true, tapActive: false) == .needsTap)
    #expect(SetupReadiness(trusted: true, pairReady: true, tapActive: true) == .ready)
}

@Test func setupCompletionSurvivesRelaunchWithoutChangingThePair() {
    let name = "KeyflipSetupTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = SettingsStore(defaults: defaults)
    #expect(!settings.setupCompleted)
    settings.slotA = "a"
    settings.slotB = "b"
    settings.setupCompleted = true
    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.setupCompleted)
    #expect(reloaded.slotA == "a" && reloaded.slotB == "b")
}

@Test func loginErrorsAreReportedForBothRegistrationAndRemoval() {
    let error = NSError(domain: "test.service", code: 42)
    #expect(LaunchAtLogin.change(status: .notRegistered, register: { throw error }, unregister: {}) == .failed(domain: error.domain, code: 42))
    #expect(LaunchAtLogin.change(status: .enabled, register: {}, unregister: { throw error }) == .failed(domain: error.domain, code: 42))
}

@Test func loginApprovalDoesNotAttemptAnotherRegistration() {
    var called = false
    let result = LaunchAtLogin.change(status: .requiresApproval, register: { called = true }, unregister: { called = true })
    #expect(result == .requiresApproval)
    #expect(!called)
    let denied = NSError(domain: "kSMErrorDomainFramework", code: Int(kSMErrorLaunchDeniedByUser))
    #expect(LaunchAtLogin.change(status: .notRegistered, register: { throw denied }, unregister: {}) == .requiresApproval)
}

@Test func loginApprovalRecognizesTheModernErrorDomain() {
    guard #available(macOS 15, *) else { return }
    let denied = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorLaunchDeniedByUser))
    #expect(LaunchAtLogin.change(status: .notRegistered, register: { throw denied }, unregister: {}) == .requiresApproval)
}

@Test func diagnosticReportsContainSupportContextWithoutTheHomePath() {
    let report = DiagnosticReport(version: "1.2 (3)", system: "15.0", architecture: "arm64",
                                  layoutA: "layout.a", layoutB: nil, trigger: "⌥⌥", trusted: false,
                                  tapState: "inactive", pairReady: false, loginState: "off")
    let text = report.render(log: "path=/Users/example/Applications/Keyflip.app", homeDirectory: "/Users/example")
    #expect(text.contains("Keyflip 1.2 (3)"))
    #expect(text.contains("Layout A: layout.a"))
    #expect(text.contains("Layout B: unset"))
    #expect(text.contains("Accessibility: missing"))
    #expect(text.contains("~/Applications/Keyflip.app"))
    #expect(!text.contains("/Users/example"))
}
