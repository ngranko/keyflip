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

    func read() -> FieldRead {
        reads.isEmpty ? .noFocus : reads.removeFirst()
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
