import Foundation

public struct TextRange: Equatable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public var nsRange: NSRange { NSRange(location: location, length: length) }
}

public enum LastWord {
    public static func range(in text: String, caretUTF16: Int) -> TextRange? {
        let ns = text as NSString
        let caret = max(0, min(caretUTF16, ns.length))
        guard caret > 0 else { return nil }

        let prefix = ns.substring(to: caret) as String
        var end = prefix.endIndex
        while end > prefix.startIndex {
            let prev = prefix.index(before: end)
            if prefix[prev].isWhitespace {
                end = prev
            } else {
                break
            }
        }
        guard end > prefix.startIndex else { return nil }

        var start = end
        while start > prefix.startIndex {
            let prev = prefix.index(before: start)
            if prefix[prev].isWhitespace { break }
            start = prev
        }

        let startUTF16 = prefix[..<start].utf16.count
        let endUTF16 = prefix[..<end].utf16.count
        let length = endUTF16 - startUTF16
        guard length > 0 else { return nil }
        return TextRange(location: startUTF16, length: length)
    }

    public static func substring(in text: String, caretUTF16: Int) -> String? {
        guard let range = range(in: text, caretUTF16: caretUTF16) else { return nil }
        return (text as NSString).substring(with: range.nsRange)
    }
}
