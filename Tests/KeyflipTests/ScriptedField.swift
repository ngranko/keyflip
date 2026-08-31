import Foundation
import LayoutConversion
@testable import Keyflip

/// The second adapter behind `FieldReader`: readings handed out in order, so
/// an app's behaviour can be replayed without the app. Carries no field
/// handle, so a write reaching one declines instead of guessing.
final class ScriptedField: FieldReader {
    private var reads: [FieldRead]

    init(_ reads: [FieldRead] = []) {
        self.reads = reads
    }

    init(showing readings: [FieldReading]) {
        reads = readings.map { .field(FieldSnapshot(handle: .none, reading: $0)) }
    }

    /// A field that answers the same way however often it is asked, for the
    /// paths that re-read while polling.
    init(always reading: FieldReading) {
        repeating = .field(FieldSnapshot(handle: .none, reading: reading))
        reads = []
    }

    private var repeating: FieldRead?

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
    FieldSnapshot(handle: .none, reading: reading)
}
