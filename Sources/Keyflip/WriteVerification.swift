import Foundation

enum WriteVerification {
    static func classify(value: String, selection: NSRange, before: String, range: NSRange,
                         wrote text: String, over original: String) -> FieldAccess.WriteCheck {
        let value = value as NSString
        guard value.length > 0 else { return .unreadable }
        if readSlice(value, at: range.location, length: text.utf16.count) == text {
            return confirmLength(value, selection: selection, before: before, range: range, wrote: text)
        }
        if readSlice(value, at: range.location, length: original.utf16.count) == original { return .unchanged }
        return .mangled(value as String)
    }

    private static func confirmLength(_ value: NSString, selection: NSRange, before: String,
                                      range: NSRange, wrote text: String) -> FieldAccess.WriteCheck {
        // Matching output alone also accepts an insertion that left the original behind.
        guard !before.isEmpty else { return .applied }
        let expected = before.utf16.count - range.length + text.utf16.count
        if value.length == expected { return .applied }
        let completed = selection.location == range.location + text.utf16.count
            && selection.upperBound == value.length
            && value.length - selection.length == expected
        return completed ? .completed : .mangled(value as String)
    }

    static func readSlice(_ value: NSString, at location: Int, length: Int) -> String? {
        guard location >= 0, length >= 0, location + length <= value.length else { return nil }
        return value.substring(with: NSRange(location: location, length: length))
    }
}
