import Foundation

/// Whether a tap that timed out may be replaced by a fresh one.
///
/// The system disables a tap that held an event too long — that is macOS
/// handing the user back their keyboard, and the only safety net that does not
/// depend on this process being well (ADR 0009). A wake from sleep trips one,
/// so the first is worth rebuilding through. A second inside the minute is a
/// pattern, and every repeat costs someone seconds of dead input, so the tap
/// stays gone until a person grants the permission again.
struct TapHealth {
    private static let budget = 1
    private static let window: TimeInterval = 60

    private var timeouts: [TimeInterval] = []

    mutating func survivesTimeout(at now: TimeInterval) -> Bool {
        timeouts.append(now)
        timeouts.removeAll { now - $0 >= Self.window }
        return timeouts.count <= Self.budget
    }

    mutating func forget() {
        timeouts = []
    }

    /// A keystroke the system has counted but this tap has not been handed.
    ///
    /// The HID layer stamps a key the moment it is pressed, upstream of any
    /// tap, so the two clocks disagreeing means the events are stopping here.
    /// It is the only symptom visible while a tap is holding input: the
    /// callback cannot report it, because the callback is what is not running.
    static func isSwallowingInput(systemIdle: TimeInterval, tapIdle: TimeInterval) -> Bool {
        systemIdle < 2 && tapIdle > 2
    }
}
