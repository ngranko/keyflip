import Foundation

public struct Conversion: Equatable, Sendable {
    public var fromSourceID: String
    public var destinationID: String
    public var output: String

    public init(fromSourceID: String, destinationID: String, output: String) {
        self.fromSourceID = fromSourceID
        self.destinationID = destinationID
        self.output = output
    }
}

public enum ConversionDecision: Equatable, Sendable {
    case rewrite(Conversion)
    case noOp
}

public enum PairConversion {
    /// Typographic punctuation folded back to the keys that produced it.
    ///
    /// macOS substitutes smart quotes as you type, so what reaches the field
    /// is not what the key gave: an apostrophe typed on the `'`/`э` key
    /// arrives as U+2019, which sits on no layout at all. The unmapped rule
    /// (ADR 0001) then left it alone, and `этот` came back as `’тот`.
    ///
    /// Quotes only. An em dash would fold onto the hyphen key and quietly
    /// turn punctuation the user chose into punctuation they did not.
    private static let typographic: [String: String] = [
        "\u{2018}": "'",
        "\u{2019}": "'",
        "\u{201C}": "\"",
        "\u{201D}": "\"",
    ]

    /// The keystroke that produces `ch` on `map`. A direct hit always wins, so
    /// a character genuinely on a key is unaffected by the folding.
    private static func stroke(for ch: String, on map: LayoutMap) -> KeyStroke? {
        if let hit = map.reverse[ch] { return hit }
        return typographic[ch].flatMap { map.reverse[$0] }
    }

    public static func convert(
        target: String,
        slotA: LayoutMap,
        slotB: LayoutMap,
        currentSourceID: String?
    ) -> ConversionDecision {
        let chars = target.map(String.init)
        var votesA = 0
        var votesB = 0
        for ch in chars {
            let inA = stroke(for: ch, on: slotA) != nil
            let inB = stroke(for: ch, on: slotB) != nil
            if inA && !inB { votesA += 1 }
            if inB && !inA { votesB += 1 }
        }

        let from: LayoutMap
        let dest: LayoutMap
        if votesA > votesB {
            from = slotA
            dest = slotB
        } else if votesB > votesA {
            from = slotB
            dest = slotA
        } else if currentSourceID == slotA.id {
            from = slotA
            dest = slotB
        } else if currentSourceID == slotB.id {
            from = slotB
            dest = slotA
        } else {
            return .noOp
        }

        var output = ""
        for ch in chars {
            if let key = stroke(for: ch, on: from), let hit = dest.forward[key] {
                output += hit
            } else {
                output += ch
            }
        }
        return .rewrite(Conversion(
            fromSourceID: from.id,
            destinationID: dest.id,
            output: output
        ))
    }
}
