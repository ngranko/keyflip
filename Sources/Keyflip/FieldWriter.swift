import ApplicationServices
import Foundation

/// Everything the rung ladder does to a field, and nothing it decides.
///
/// Two adapters: Accessibility plus synthesized keystrokes in the app, and a
/// scripted app in tests — so the behaviours ADR 0006 and 0007 were written
/// against can be replayed without the app that taught them.
protocol FieldWriter {
    func replace(
        _ snapshot: FieldSnapshot,
        range: NSRange,
        with newText: String
    ) -> FieldAccess.WriteAttempt

    func verify(
        _ snapshot: FieldSnapshot,
        range: NSRange,
        wrote newText: String,
        over original: String
    ) -> FieldAccess.WriteCheck

    func select(_ snapshot: FieldSnapshot, range: NSRange, expecting text: String) -> Bool
    func restoreCaret(_ snapshot: FieldSnapshot) -> Bool
    func typeKeys(deleting count: Int, with text: String) -> Bool
}

struct AXFieldWriter: FieldWriter {
    func replace(
        _ snapshot: FieldSnapshot,
        range: NSRange,
        with newText: String
    ) -> FieldAccess.WriteAttempt {
        FieldAccess.replace(snapshot, range: range, with: newText)
    }

    func verify(
        _ snapshot: FieldSnapshot,
        range: NSRange,
        wrote newText: String,
        over original: String
    ) -> FieldAccess.WriteCheck {
        FieldAccess.verify(snapshot, range: range, wrote: newText, over: original)
    }

    func select(_ snapshot: FieldSnapshot, range: NSRange, expecting text: String) -> Bool {
        FieldAccess.select(snapshot, range: range, expecting: text)
    }

    func restoreCaret(_ snapshot: FieldSnapshot) -> Bool {
        FieldAccess.restoreCaret(snapshot)
    }

    func typeKeys(deleting count: Int, with text: String) -> Bool {
        KeyboardOutput.replace(deleting: count, with: text)
    }
}

/// When the rewriter's waits elapse. The app waits on the main queue, where a
/// rewrite has to settle in real time; a test runs the work at once, so a
/// ten-step recovery poll costs nothing to exercise.
protocol Wait {
    func after(_ delay: TimeInterval, then work: @escaping () -> Void)
}

struct MainQueueWait: Wait {
    func after(_ delay: TimeInterval, then work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
