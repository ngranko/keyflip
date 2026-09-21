import Testing
@testable import Keyflip

@Test func repeatedTriggersDoNotPostponeAccessibilityActivation() {
    var activation = AccessibilityActivation()
    activation.begin(for: 123, now: 0)
    for instant in [0.5, 1, 1.5, 2] { activation.begin(for: 123, now: instant) }
    #expect(activation.remainingDelay(for: 123, now: 2.5) == 0)
}

@Test func activationWaitsAreIndependentAcrossApps() {
    var activation = AccessibilityActivation()
    activation.begin(for: 123, now: 0)
    activation.begin(for: 456, now: 1)
    #expect(activation.remainingDelay(for: 123, now: 2.5) == 0)
    #expect(activation.remainingDelay(for: 456, now: 2.5) == 1)
}

@Test func failedActivationDoesNotDelayTheTrigger() {
    var activation = AccessibilityActivation()
    activation.begin(for: 123, now: 0)
    activation.cancel(for: 123)
    #expect(activation.remainingDelay(for: 123, now: 0) == 0)
}
