import ApplicationServices
import Foundation

// AX timeouts apply to individual messages; a field operation needs a shared deadline.
enum AXBudget {
    private static let key = "Keyflip.AXDeadline"
    static let textLimit = 65_536

    static func run<T>(_ work: () -> T) -> T {
        let previous = Thread.current.threadDictionary[key]
        Thread.current.threadDictionary[key] = ProcessInfo.processInfo.systemUptime + 0.3
        defer { Thread.current.threadDictionary[key] = previous }
        return work()
    }

    static var expired: Bool { remaining <= 0 }

    private static var remaining: TimeInterval {
        guard let deadline = Thread.current.threadDictionary[key] as? TimeInterval else { return 0.1 }
        return deadline - ProcessInfo.processInfo.systemUptime
    }

    static func prepare(_ element: AXUIElement) -> Bool {
        let remaining = remaining
        guard remaining > 0 else { return false }
        AXUIElementSetMessagingTimeout(element, Float(min(0.1, remaining)))
        return true
    }
}
