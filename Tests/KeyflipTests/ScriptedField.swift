import ApplicationServices
import Foundation
import LayoutConversion
@testable import Keyflip

/// The second adapter behind `FieldReader`: readings handed out in order, so
/// an app's behaviour can be replayed without the app. Carries no field
/// handle, so a write reaching one declines instead of guessing.
final class ScriptedField: FieldReader {
    private var reads: [FieldRead]
    var focusedHandle: FieldHandle?

    init(_ reads: [FieldRead] = []) {
        self.reads = reads
        if case .field(let snapshot) = reads.first { focusedHandle = snapshot.handle }
    }

    init(showing readings: [FieldReading]) {
        reads = readings.map { .field(snapshot($0)) }
        focusedHandle = readings.first.map { snapshot($0).handle }
    }

    /// A field that answers the same way however often it is asked, for the
    /// paths that re-read while polling.
    init(always reading: FieldReading) {
        repeating = .field(snapshot(reading))
        focusedHandle = snapshot(reading).handle
        reads = []
    }

    var repeating: FieldRead?

    func isFocused(_ snapshot: FieldSnapshot) -> Bool {
        focusedHandle?.matches(snapshot.handle) == true
    }

    func read() -> FieldRead {
        if let repeating { return repeating }
        return reads.isEmpty ? .noFocus : reads.removeFirst()
    }
}

func reading(
    app: String = "TestApp",
    role: String = "AXTextArea",
    value: String,
    caret: Int,
    selectionLength: Int = 0,
    selectedText: String = ""
) -> FieldReading {
    FieldReading(
        app: app,
        role: role,
        value: value,
        selectedRange: NSRange(location: caret, length: selectionLength),
        selectedText: selectedText
    )
}

func snapshot(_ reading: FieldReading) -> FieldSnapshot {
    FieldSnapshot(
        handle: .ax(AXUIElementCreateApplication(Int32(truncatingIfNeeded: reading.app.hashValue))),
        reading: reading
    )
}
