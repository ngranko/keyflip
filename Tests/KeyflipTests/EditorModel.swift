import Foundation
import LayoutConversion
@testable import Keyflip

final class EditorModel: FieldReader, FieldWriter {
    var current: FieldSnapshot
    var acceptsAX = true
    var leavesCaretAtStart = false
    var refusedCaretMoves = 0
    private(set) var caretMoves = 0
    var dropNextInsertion = false
    var insertWithoutReplacing = false
    var delaysSelection = false
    private var deliveries: [() -> Void] = []
    private(set) var keyWrites = 0

    init(_ text: String) { current = snapshot(reading(value: text, caret: text.utf16.count)) }
    func read() -> FieldRead { .field(current) }
    func isFocused(_ snapshot: FieldSnapshot) -> Bool { current.handle.matches(snapshot.handle) }
    func deliver() { let pending = deliveries; deliveries = []; pending.forEach { $0() } }

    func replace(_ snapshot: FieldSnapshot, range: NSRange, with text: String) -> FieldAccess.WriteAttempt {
        guard acceptsAX else { return .refused }
        deliveries.append { self.apply(text, to: range) }
        return .wrote
    }

    func verify(_ snapshot: FieldSnapshot, range: NSRange, wrote text: String, over original: String) -> FieldAccess.WriteCheck {
        let expected = (snapshot.reading.value as NSString).replacingCharacters(in: range, with: text)
        if current.reading.value == expected { return .applied }
        if current.reading.value == snapshot.reading.value { return .unchanged }
        return .mangled(current.reading.value)
    }

    func select(_ snapshot: FieldSnapshot, range: NSRange, expecting text: String) -> Bool {
        let value = current.reading.value as NSString
        guard range.upperBound <= value.length, value.substring(with: range) == text else { return false }
        if delaysSelection {
            deliveries.append {
                self.current.reading.selectedRange = range
                self.current.reading.selectedText = text
            }
            return false
        }
        current.reading.selectedRange = range
        current.reading.selectedText = text
        return true
    }

    func restoreCaret(_ snapshot: FieldSnapshot, expecting text: String) -> FieldAccess.CaretRestore {
        caretMoves += 1
        if refusedCaretMoves > 0 { refusedCaretMoves -= 1; return .wrongPosition }
        current.reading.selectedRange = NSRange(location: snapshot.reading.selectedRange.upperBound, length: 0)
        current.reading.selectedText = ""
        return FieldAccess.confirmCaret(current.reading.selectedRange, at: snapshot.reading.selectedRange.upperBound,
                                        in: current.reading.value, expecting: text)
    }

    func typeKeys(deleting count: Int, with text: String) -> Bool {
        keyWrites += 1
        deliveries.append {
            let selection = self.current.reading.selectedRange
            let remaining = max(0, count - (selection.length > 0 ? 1 : 0))
            let range = NSRange(location: selection.location - remaining, length: selection.length + remaining)
            self.apply(self.dropNextInsertion ? "" : text, to: range)
            self.dropNextInsertion = false
        }
        return true
    }

    private func apply(_ text: String, to range: NSRange) {
        let range = insertWithoutReplacing ? NSRange(location: range.location, length: 0) : range
        current.reading.value = (current.reading.value as NSString).replacingCharacters(in: range, with: text)
        current.reading.selectedRange = NSRange(location: range.location + (leavesCaretAtStart ? 0 : text.utf16.count), length: 0)
        current.reading.selectedText = ""
    }
}

@MainActor
final class ManualWait: Wait {
    private var callbacks: [() -> Void] = []
    func after(_ delay: TimeInterval, then work: @escaping () -> Void) { callbacks.append(work) }
    func advance() { if !callbacks.isEmpty { callbacks.removeFirst()() } }
}
