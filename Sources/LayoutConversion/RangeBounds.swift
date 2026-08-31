import Foundation

extension NSRange {
    /// This range trimmed to what `text` actually holds.
    public func clamped(in text: String) -> NSRange {
        let len = (text as NSString).length
        let loc = max(0, min(location, len))
        let end = max(loc, min(location + length, len))
        return NSRange(location: loc, length: end - loc)
    }

    /// Whether nothing but whitespace lies outside this range — what a caller
    /// asks before replacing a field wholesale.
    public func spansEverything(in text: String) -> Bool {
        let ns = text as NSString
        guard location >= 0, length >= 0, upperBound <= ns.length else { return false }
        return ns.substring(to: location).allSatisfy(\.isWhitespace)
            && ns.substring(from: upperBound).allSatisfy(\.isWhitespace)
    }
}
