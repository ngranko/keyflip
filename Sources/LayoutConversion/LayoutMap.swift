import Carbon
import Foundation

public struct KeyStroke: Hashable, Sendable {
    public var key: UInt16
    public var mods: UInt32

    public init(key: UInt16, mods: UInt32) {
        self.key = key
        self.mods = mods
    }

    public static var shiftMods: UInt32 { UInt32(shiftKey >> 8) }
}

public struct LayoutMap: Sendable {
    public var id: String
    public var name: String
    public var reverse: [String: KeyStroke]
    public var forward: [KeyStroke: String]

    public init(id: String, name: String, reverse: [String: KeyStroke], forward: [KeyStroke: String]) {
        self.id = id
        self.name = name
        self.reverse = reverse
        self.forward = forward
    }
}

public enum LayoutMapBuilder {
    private static let keypad: Set<UInt16> = [
        0x41, 0x43, 0x45, 0x47, 0x4B, 0x4C, 0x4E, 0x51,
        0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C,
    ]

    public static func build(id: String, name: String, layoutData: Data) -> LayoutMap? {
        layoutData.withUnsafeBytes { raw -> LayoutMap? in
            guard let base = raw.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            return build(id: id, name: name, layout: layout)
        }
    }

    public static func build(
        id: String,
        name: String,
        layout: UnsafePointer<UCKeyboardLayout>
    ) -> LayoutMap {
        let layers: [UInt32] = [0, KeyStroke.shiftMods]
        let mainKeys = (UInt16(0)..<128).filter { !keypad.contains($0) }
        let padKeys = (UInt16(0)..<128).filter { keypad.contains($0) }

        var reverse: [String: KeyStroke] = [:]
        var forward: [KeyStroke: String] = [:]
        // Main keys first, so a character that sits on both wins from the one
        // the user actually types it on rather than from the keypad.
        for key in mainKeys + padKeys {
            for mods in layers {
                guard let s = translate(layout, key: key, mods: mods), !s.isEmpty else { continue }
                let stroke = KeyStroke(key: key, mods: mods)
                if reverse[s] == nil {
                    reverse[s] = stroke
                }
                if forward[stroke] == nil {
                    forward[stroke] = s
                }
            }
        }
        return LayoutMap(id: id, name: name, reverse: reverse, forward: forward)
    }

    static func translate(
        _ layout: UnsafePointer<UCKeyboardLayout>,
        key: UInt16,
        mods: UInt32
    ) -> String? {
        var dead: UInt32 = 0
        var chars: [UniChar] = Array(repeating: 0, count: 8)
        var len = 0
        let err = UCKeyTranslate(
            layout,
            key,
            UInt16(kUCKeyActionDisplay),
            mods,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &dead,
            8,
            &len,
            &chars
        )
        guard err == noErr, len > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: len)
    }
}
