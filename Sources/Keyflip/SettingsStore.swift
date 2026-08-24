import Foundation
import LayoutConversion

final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private enum Key {
        static let slotA = "slotA"
        static let slotB = "slotB"
        static let trigger = "trigger"
        static let axWriteRefused = "axWriteRefused"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var slotA: String? {
        get { defaults.string(forKey: Key.slotA) }
        set { defaults.set(newValue, forKey: Key.slotA) }
    }

    var slotB: String? {
        get { defaults.string(forKey: Key.slotB) }
        set { defaults.set(newValue, forKey: Key.slotB) }
    }

    var trigger: Trigger {
        get {
            guard let data = defaults.data(forKey: Key.trigger),
                  let value = try? JSONDecoder().decode(Trigger.self, from: data)
            else { return .default }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.trigger)
            }
        }
    }

    /// Apps proven to discard Accessibility writes.
    ///
    /// Learned once and kept. An app does not change its mind between
    /// launches, and re-learning it costs a failed conversion on the first
    /// trigger of every launch — which, for anyone rebuilding the app, is
    /// most of the conversions they attempt.
    var axWriteRefused: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.axWriteRefused) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Key.axWriteRefused) }
    }

    func pairIDs() -> (String, String)? {
        guard let a = slotA, let b = slotB, a != b else { return nil }
        return (a, b)
    }

    func seedIfNeeded(layouts: [InputSourceInfo]) {
        if let a = slotA, let b = slotB, a != b { return }
        let abc = layouts.first { $0.id == "com.apple.keylayout.ABC" }
        let rus = layouts.first { $0.id == "com.apple.keylayout.RussianWin" }
        if let abc, let rus {
            slotA = abc.id
            slotB = rus.id
            return
        }
        guard layouts.count >= 2 else { return }
        slotA = layouts[0].id
        slotB = layouts[1].id
    }

    func setSlotA(_ id: String) {
        if id == slotB { return }
        slotA = id
    }

    func setSlotB(_ id: String) {
        if id == slotA { return }
        slotB = id
    }
}
