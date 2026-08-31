import Foundation

/// What a trigger saw in the focused field, as plain values. Carries no live
/// Accessibility handle, so every decision made from a reading can be made
/// again from a reading written down in a test.
public struct FieldReading: Equatable, Sendable {
    /// Only for the log, and the first thing wanted in a bug report.
    public var app: String
    public var role: String
    public var value: String
    public var selectedRange: NSRange
    public var selectedText: String

    public init(
        app: String,
        role: String,
        value: String,
        selectedRange: NSRange,
        selectedText: String
    ) {
        self.app = app
        self.role = role
        self.value = value
        self.selectedRange = selectedRange
        self.selectedText = selectedText
    }
}
