import ApplicationServices
import Testing
@testable import Keyflip

@Test func recoverApplicationWhenSystemAXReportsNoValue() {
    let result = FocusedApplication.resolve(readSystem: { (.noValue, nil) }, findFrontmostPID: { 123 })
    guard case .found(let app) = result else {
        Issue.record("Expected the frontmost application despite the missing system AX focus")
        return
    }
    var pid: pid_t = 0
    AXUIElementGetPid(app, &pid)
    #expect(pid == 123)
}

@Test func keepApplicationReportedBySystemAX() {
    let original = AXUIElementCreateApplication(123)
    let result = FocusedApplication.resolve(readSystem: { (.success, original) }, findFrontmostPID: {
        Issue.record("A successful AX lookup must not use the fallback")
        return nil
    })
    guard case .found(let app) = result else { Issue.record("Expected application"); return }
    #expect(CFEqual(app, original))
}

@Test func missingPermissionDoesNotFallBackToWorkspace() {
    let result = FocusedApplication.resolve(readSystem: { (.apiDisabled, nil) }, findFrontmostPID: {
        Issue.record("A permission failure must remain unavailable")
        return 123
    })
    guard case .unavailable = result else { Issue.record("Expected unavailable"); return }
}

@Test func absentFrontmostApplicationRemainsMissing() {
    let result = FocusedApplication.resolve(readSystem: { (.noValue, nil) }, findFrontmostPID: { nil })
    guard case .missing = result else { Issue.record("Expected missing"); return }
}
