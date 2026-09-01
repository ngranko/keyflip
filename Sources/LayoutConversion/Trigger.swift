import Foundation

public enum ModifierKey: String, Codable, Sendable, CaseIterable {
    case option
    case control
    case command

    public var keyCodes: [UInt16] {
        switch self {
        case .option: return [0x3A, 0x3D]
        case .control: return [0x3B, 0x3E]
        case .command: return [0x37, 0x36]
        }
    }

    public var flagBit: UInt64 {
        switch self {
        case .option: return 1 << 19
        case .control: return 1 << 18
        case .command: return 1 << 20
        }
    }

    public var glyph: String {
        switch self {
        case .option: return "⌥"
        case .control: return "⌃"
        case .command: return "⌘"
        }
    }
}

public struct Chord: Equatable, Codable, Sendable {
    public var modifiers: UInt64
    public var keyCode: UInt16

    public init(modifiers: UInt64, keyCode: UInt16) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }
}

public enum Trigger: Equatable, Codable, Sendable {
    case doubleTap(ModifierKey)
    case chord(Chord)

    public static let `default` = Trigger.doubleTap(.option)

    public var glyph: String {
        switch self {
        case .doubleTap(let mod):
            return "\(mod.glyph)\(mod.glyph)"
        case .chord(let chord):
            return Self.modifierGlyphs(chord.modifiers) + Self.keyLabel(chord.keyCode)
        }
    }

    /// Shift has no `ModifierKey` case — a trigger cannot be a double-tap of
    /// it, because Shift alone is how the next character is capitalised — but
    /// a chord may still name it.
    private static let shiftFlag: UInt64 = 1 << 17

    /// Every bit a trigger may name, in the order macOS writes them.
    private static let namedModifiers: [(bit: UInt64, glyph: String)] = [
        (ModifierKey.control.flagBit, ModifierKey.control.glyph),
        (ModifierKey.option.flagBit, ModifierKey.option.glyph),
        (shiftFlag, "⇧"),
        (ModifierKey.command.flagBit, ModifierKey.command.glyph),
    ]

    /// Caps Lock, Fn, and the numeric-pad bit must not reject a match.
    public static let relevantModifiers: UInt64 = namedModifiers.reduce(0) { $0 | $1.bit }

    public static func modifierGlyphs(_ flags: UInt64) -> String {
        namedModifiers.filter { flags & $0.bit != 0 }.map(\.glyph).joined()
    }

    public static func keyLabel(_ keyCode: UInt16) -> String {
        KeyCodeNames.name(keyCode) ?? "•"
    }
}

public struct TapEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case keyDown
        case flagsChanged
        case mouseDown
    }

    public var kind: Kind
    public var keyCode: UInt16
    public var flags: UInt64
    /// What the system resolved this keystroke to, when it resolved to text.
    public var characters: String

    public init(kind: Kind, keyCode: UInt16, flags: UInt64, characters: String = "") {
        self.kind = kind
        self.keyCode = keyCode
        self.flags = flags
        self.characters = characters
    }

    public var independentFlags: UInt64 {
        flags & 0xFFFF0000
    }
}

public enum TriggerMatch: Equatable, Sendable {
    case none
    case fired
}

public final class TriggerRecognizer: @unchecked Sendable {
    public var trigger: Trigger
    public var interval: TimeInterval
    private var lastFlags: UInt64 = 0
    private enum Pending {
        case down(ModifierKey, isSecond: Bool)
        case firstTap(ModifierKey, TimeInterval)
    }
    private var pending: Pending?

    public init(trigger: Trigger = .default, interval: TimeInterval) {
        self.trigger = trigger
        self.interval = interval
    }

    public func reset() {
        pending = nil
    }

    public func handle(_ event: TapEvent, at time: TimeInterval) -> TriggerMatch {
        switch trigger {
        case .doubleTap(let mod):
            return handleDoubleTap(mod, event, at: time)
        case .chord(let chord):
            return handleChord(chord, event)
        }
    }

    private func handleChord(_ chord: Chord, _ event: TapEvent) -> TriggerMatch {
        pending = nil
        guard event.kind == .keyDown else { return .none }
        guard event.keyCode == chord.keyCode else { return .none }
        let relevant = Trigger.relevantModifiers
        guard event.independentFlags & relevant == chord.modifiers & relevant else { return .none }
        return .fired
    }

    private func handleDoubleTap(_ want: ModifierKey, _ event: TapEvent, at time: TimeInterval) -> TriggerMatch {
        if event.kind == .keyDown {
            pending = nil
            lastFlags = event.independentFlags
            return .none
        }
        guard event.kind == .flagsChanged else { return .none }

        let prev = lastFlags
        let next = event.independentFlags
        lastFlags = next

        let bit = want.flagBit
        let wasDown = prev & bit != 0
        let isDown = next & bit != 0
        let relevant = Trigger.relevantModifiers
        let othersPrev = prev & ~bit & relevant
        let othersNext = next & ~bit & relevant
        if othersPrev != 0 || othersNext != 0 {
            pending = nil
            return .none
        }

        // Quartz often reports keyCode 0 on flagsChanged. Match the modifier
        // bit, not the keycode. Ignore events that did not change this bit
        // (duplicate tap+monitor deliveries, Caps Lock, Fn).
        if wasDown == isDown {
            return .none
        }

        if !wasDown && isDown {
            if case .firstTap(let mod, let firstTime) = pending, mod == want, time - firstTime <= interval {
                pending = .down(want, isSecond: true)
            } else {
                pending = .down(want, isSecond: false)
            }
            return .none
        }
        if wasDown && !isDown {
            switch pending {
            case .down(let mod, let isSecond) where mod == want:
                if isSecond {
                    pending = nil
                    return .fired
                }
                pending = .firstTap(want, time)
                return .none
            default:
                pending = nil
                return .none
            }
        }
        pending = nil
        return .none
    }
}

/// Watches raw events while the user is binding a new trigger: a double-tap of
/// any of the three modifiers, or modifier(s) plus one key. Esc cancels.
public final class Recorder: @unchecked Sendable {
    private let doubleTaps: [(ModifierKey, TriggerRecognizer)]

    public init(interval: TimeInterval) {
        doubleTaps = ModifierKey.allCases.map {
            ($0, TriggerRecognizer(trigger: .doubleTap($0), interval: interval))
        }
    }

    public enum Result: Equatable, Sendable {
        case none
        case cancel
        case captured(Trigger)
    }

    public func handle(_ event: TapEvent, at time: TimeInterval) -> Result {
        if event.kind == .keyDown, event.keyCode == 0x35 {
            return .cancel
        }
        for (mod, recognizer) in doubleTaps where recognizer.handle(event, at: time) == .fired {
            return .captured(.doubleTap(mod))
        }
        guard event.kind == .keyDown, !Self.isModifierKey(event.keyCode) else { return .none }
        let mods = event.independentFlags & Trigger.relevantModifiers
        guard mods != 0 else { return .none }
        return .captured(.chord(Chord(modifiers: mods, keyCode: event.keyCode)))
    }

    private static func isModifierKey(_ keyCode: UInt16) -> Bool {
        // Command, Option, Control, plus Shift, Caps Lock, and Fn.
        ModifierKey.allCases.flatMap(\.keyCodes).contains(keyCode)
            || [0x38, 0x3C, 0x39, 0x3F].contains(keyCode)
    }
}

enum KeyCodeNames {
    static func name(_ keyCode: UInt16) -> String? {
        let map: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
            0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
            0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x12: "1",
            0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
            0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L",
            0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",",
            0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`", 0x31: "Space",
            0x24: "↩", 0x30: "⇥", 0x33: "⌫", 0x35: "Esc",
        ]
        return map[keyCode]
    }
}
