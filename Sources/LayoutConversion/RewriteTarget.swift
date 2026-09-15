import Foundation

public enum RewriteTarget {
    public static func includeTrailingSpace(_ target: Target, output: String, in reading: FieldReading) -> (Target, String) {
        let caret = reading.selectedRange.location
        let value = reading.value as NSString
        guard reading.selectedRange.length == 0, reading.selectedText.isEmpty,
              target.range.location >= 0, target.range.length >= 0,
              target.range.upperBound <= caret, caret <= value.length else { return (target, output) }
        let trailing = value.substring(with: NSRange(location: target.range.upperBound, length: caret - target.range.upperBound))
        guard trailing.allSatisfy(\.isWhitespace) else { return (target, output) }
        return (Target(text: target.text + trailing,
                       range: NSRange(location: target.range.location, length: caret - target.range.location)), output + trailing)
    }
}
