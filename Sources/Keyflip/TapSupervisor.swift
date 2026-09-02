import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

/// Owns the tap's whole life: arms one when the grant allows it, and never
/// lets one outlive this process's ability to answer it.
///
/// Trust is not the signal it looks like. Through the half-minute of dead
/// keyboard that ADR 0009 came from, `AXIsProcessTrusted` went on answering
/// yes, long after the checkbox had been unticked. What the window server will
/// actually build is the honest answer, so the tap itself is the probe: try to
/// create one, and take a refusal as the grant being gone.
///
/// All of it runs on its own queue, so a stalled main thread cannot delay a
/// teardown by so much as a keystroke.
final class TapSupervisor: @unchecked Sendable {
    private static let interval: TimeInterval = 1.5

    /// Posted when the Accessibility list changes, for any app. Cheap to
    /// over-react to: the tap is rebuilt within a couple of seconds either way.
    private static let grantsChanged = Notification.Name("com.apple.accessibility.api")

    private let tap: EventTap
    private let queue = DispatchQueue(label: "local.Keyflip.tapsupervisor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var wasTrusted = true
    private var loggedRefusal = false

    init(tap: EventTap) {
        self.tap = tap
    }

    /// Arms the tap before returning, so a launch with the grant already given
    /// has one by the time the app reports its state.
    func start() {
        check()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval)
        timer.setEventHandler { [weak self] in self?.check() }
        self.timer = timer
        timer.resume()
        watchForGrantChanges()
    }

    private func watchForGrantChanges() {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.grantsChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            queue.async { self.rebuild() }
        }
    }

    /// Runs on `queue`, which is serial, and once on the launching thread
    /// before that queue has any work.
    private func check() {
        let trusted = AXIsProcessTrusted()
        let regained = trusted && !wasTrusted
        wasTrusted = trusted
        // ADR 0004: ask on every lapse, not once per launch.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Permissions.promptIfAccessibilityLapsed(available: trusted)
            }
        }
        // Trust saying no is still worth acting on at once; trust saying yes
        // proves nothing, which is why arming is left to the tap itself.
        if !trusted { revoke() }
        if regained { tap.rearm() }
        tearDownIfSwallowingInput()
        arm()
    }

    /// Keystrokes the system has counted while the tap has been handed none.
    ///
    /// The one symptom of held input that is visible from anywhere: the
    /// callback cannot report it, since not being called is the fault. Secure
    /// input withholds keys from every tap by design, and is not this
    /// (ADR 0009).
    private func tearDownIfSwallowingInput() {
        guard tap.isActive, !IsSecureEventInputEnabled() else { return }
        let systemIdle = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .keyDown
        )
        guard TapHealth.isSwallowingInput(
            systemIdle: systemIdle,
            tapIdle: tap.secondsSinceKeyDown
        ) else { return }
        tap.giveUp("keys reaching the system but not the tap")
    }

    /// The grant may have gone. Make the tap prove otherwise rather than
    /// waiting to be told by an event nobody can type.
    private func rebuild() {
        guard tap.isActive else { return }
        DebugLog.event("accessibility list changed → tap rebuilt")
        tap.stop()
        arm()
    }

    private func revoke() {
        guard tap.isActive else { return }
        DebugLog.event("accessibility revoked → tap torn down")
        tap.stop()
    }

    private func arm() {
        guard !tap.isActive else { return }
        if tap.start() {
            loggedRefusal = false
            DebugLog.event("tap active (\(tap.modeDescription))")
            return
        }
        // This runs every couple of seconds; say it once.
        if !loggedRefusal {
            loggedRefusal = true
            DebugLog.event("no tap: \(tap.isRetired ? "retired after timing out" : "refused, grant missing")")
        }
    }
}
