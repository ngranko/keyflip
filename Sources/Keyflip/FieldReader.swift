import ApplicationServices
import LayoutConversion

/// The live Accessibility element a reading came from.
///
/// Only `FieldAccess` dereferences it. A reading replayed in a test carries
/// `.none`, and every write against that declines rather than reaching for an
/// element that was never there.
struct FieldHandle {
    let element: AXUIElement?

    static func ax(_ element: AXUIElement) -> FieldHandle { FieldHandle(element: element) }
    static var none: FieldHandle { FieldHandle(element: nil) }
}

struct FieldSnapshot {
    var handle: FieldHandle
    var reading: FieldReading
}

/// What a trigger found under the caret. The cases carry the follow policy
/// (ADR 0004): `field` converts, `noFocus` toggles, the rest are silent.
enum FieldRead {
    case field(FieldSnapshot)
    case noFocus
    case markedText
    case secure
    case unavailable

    /// Whether the AX API answered at all. Every other case is a verdict about
    /// the field; `unavailable` is a verdict about our own grant.
    var accessibilityAvailable: Bool {
        if case .unavailable = self { return false }
        return true
    }
}

/// Where a reading comes from. Accessibility in the app, a scripted list in
/// tests — so the app behaviours the ADRs describe can be replayed without the
/// app.
protocol FieldReader {
    func read() -> FieldRead
}

struct AXFieldReader: FieldReader {
    func read() -> FieldRead { FieldAccess.read() }
}
