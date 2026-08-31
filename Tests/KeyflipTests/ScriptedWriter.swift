import Foundation
@testable import Keyflip

/// The second adapter behind `FieldWriter`: an app whose every answer is
/// written down in advance, so a rung ladder that only ever ran against real
/// editors can be walked deliberately. The last scripted answer repeats, since
/// the ladder retries and an app that refuses keeps refusing.
final class ScriptedWriter: FieldWriter {
    enum Call: Equatable {
        case replace(NSRange, String)
        case verify
        case select(NSRange, String)
        case restoreCaret
        case typeKeys(deleting: Int, with: String)
    }

    private(set) var calls: [Call] = []

    var replaceAnswers: [FieldAccess.WriteAttempt] = [.wrote]
    var verifyAnswers: [FieldAccess.WriteCheck] = [.applied]
    var selectAnswers: [Bool] = [true]
    var restoreCaretAnswers: [Bool] = [true]
    var typeKeysAnswers: [Bool] = [true]

    var verifyCount: Int { calls.filter { $0 == .verify }.count }

    private func next<T>(_ answers: inout [T]) -> T {
        answers.count > 1 ? answers.removeFirst() : answers[0]
    }

    func replace(
        _ snapshot: FieldSnapshot,
        range: NSRange,
        with newText: String
    ) -> FieldAccess.WriteAttempt {
        calls.append(.replace(range, newText))
        return next(&replaceAnswers)
    }

    func verify(
        _ snapshot: FieldSnapshot,
        range: NSRange,
        wrote newText: String,
        over original: String
    ) -> FieldAccess.WriteCheck {
        calls.append(.verify)
        return next(&verifyAnswers)
    }

    func select(_ snapshot: FieldSnapshot, range: NSRange, expecting text: String) -> Bool {
        calls.append(.select(range, text))
        return next(&selectAnswers)
    }

    func restoreCaret(_ snapshot: FieldSnapshot) -> Bool {
        calls.append(.restoreCaret)
        return next(&restoreCaretAnswers)
    }

    func typeKeys(deleting count: Int, with text: String) -> Bool {
        calls.append(.typeKeys(deleting: count, with: text))
        return next(&typeKeysAnswers)
    }
}

/// Every wait taken at once, so the confirm rechecks and the recovery poll cost
/// a test nothing to walk through.
struct ImmediateWait: Wait {
    func after(_ delay: TimeInterval, then work: @escaping () -> Void) { work() }
}
