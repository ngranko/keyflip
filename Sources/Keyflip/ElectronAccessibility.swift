import ApplicationServices
import AppKit
import os

enum ElectronAccessibility {
    private static let activation = OSAllocatedUnfairLock(initialState: AccessibilityActivation())

    static func prepareFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        AXBudget.run { enableIfNeeded(in: AXUIElementCreateApplication(app.processIdentifier)) }
    }

    static func remainingDelay(for pid: pid_t) -> TimeInterval {
        activation.withLock { $0.remainingDelay(for: pid, now: ProcessInfo.processInfo.systemUptime) }
    }

    static func enableIfNeeded(in app: AXUIElement) {
        // Chromium also activates native AX support when assistive clients read
        // the application role. Focus and title queries alone do not do this.
        guard AXBudget.prepare(app) else { return }
        var role: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(app, kAXRoleAttribute as CFString, &role)
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success, remainingDelay(for: pid) == 0 else { return }
        let attribute = "AXManualAccessibility" as CFString
        guard AXBudget.prepare(app) else { return }
        var value: CFTypeRef?
        let read = AXUIElementCopyAttributeValue(app, attribute, &value)
        // Only opt in when the app exposes Electron's switch and has it disabled.
        guard read == .success, let value,
              CFGetTypeID(value) == CFBooleanGetTypeID(),
              !CFBooleanGetValue((value as! CFBoolean)),
              AXBudget.prepare(app) else { return }
        activation.withLock { [pid] in $0.begin(for: pid, now: ProcessInfo.processInfo.systemUptime) }
        let result = AXUIElementSetAttributeValue(app, attribute, kCFBooleanTrue)
        if result != .success { activation.withLock { [pid] in $0.cancel(for: pid) } }
        DebugLog.event("ax enable manual accessibility \(axName(result))")
    }
}

struct AccessibilityActivation {
    private var deadlines: [pid_t: TimeInterval] = [:]

    mutating func begin(for pid: pid_t, now: TimeInterval) {
        guard remainingDelay(for: pid, now: now) == 0 else { return }
        deadlines = deadlines.filter { $0.value > now }
        // Electron debounces activation for two seconds; another write restarts it.
        deadlines[pid] = now + 2.5
    }

    func remainingDelay(for pid: pid_t, now: TimeInterval) -> TimeInterval {
        max(0, (deadlines[pid] ?? now) - now)
    }

    mutating func cancel(for pid: pid_t) { deadlines.removeValue(forKey: pid) }
}
