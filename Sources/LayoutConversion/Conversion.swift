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
            let inA = slotA.reverse[ch] != nil
            let inB = slotB.reverse[ch] != nil
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
            if let stroke = from.reverse[ch], let hit = dest.forward[stroke] {
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
