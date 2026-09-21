import AppKit
import ApplicationServices

enum FocusedApplication {
    enum Result {
        case found(AXUIElement)
        case unavailable
        case missing
    }

    static func resolve(
        readSystem: () -> (AXError, AXUIElement?),
        findFrontmostPID: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    ) -> Result {
        let (error, element) = readSystem()
        if error == .apiDisabled { return .unavailable }
        if error == .success, let element { return .found(element) }
        // The system AX object can lose the application as well as its field.
        // Workspace discovers the process independently of that AX lookup.
        guard let pid = findFrontmostPID(), pid > 0 else { return .missing }
        DebugLog.event("ax focusedApplication \(axName(error)) → frontmost pid=\(pid)")
        return .found(AXUIElementCreateApplication(pid))
    }
}
