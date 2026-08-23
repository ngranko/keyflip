import Carbon
import Foundation

public struct InputSourceInfo: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var layoutData: Data

    public init(id: String, name: String, layoutData: Data) {
        self.id = id
        self.name = name
        self.layoutData = layoutData
    }
}

public enum InputSources {
    public static func enabledKeyboardLayouts() -> [InputSourceInfo] {
        list(includeAllInstalled: false)
    }

    /// Falls back to the installed-but-disabled list: a slot can point at a
    /// source the user has since turned off.
    public static func layout(id: String) -> InputSourceInfo? {
        lookup(id: id, includeAllInstalled: false) ?? lookup(id: id, includeAllInstalled: true)
    }

    public static func currentID() -> String? {
        guard let unmanaged = TISCopyCurrentKeyboardInputSource() else { return nil }
        let src = unmanaged.takeRetainedValue()
        return stringProperty(src, kTISPropertyInputSourceID)
    }

    public static func currentLayoutID() -> String? {
        guard let unmanaged = TISCopyCurrentKeyboardLayoutInputSource() else { return nil }
        let src = unmanaged.takeRetainedValue()
        return stringProperty(src, kTISPropertyInputSourceID)
    }

    @discardableResult
    public static func select(_ id: String) -> Bool {
        if select(id, includeAllInstalled: false) { return true }
        return select(id, includeAllInstalled: true)
    }

    private static func select(_ id: String, includeAllInstalled: Bool) -> Bool {
        guard let unmanaged = TISCreateInputSourceList(
            [kTISPropertyInputSourceID: id] as CFDictionary,
            includeAllInstalled
        ) else { return false }
        let list = unmanaged.takeRetainedValue() as! [TISInputSource]
        guard let src = list.first else { return false }
        return TISSelectInputSource(src) == noErr
    }

    public static func map(for info: InputSourceInfo) -> LayoutMap? {
        LayoutMapBuilder.build(id: info.id, name: info.name, layoutData: info.layoutData)
    }

    /// Watch for the user enabling or removing keyboard layouts. Keep the
    /// returned token alive; releasing it unregisters.
    public static func observeEnabledChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        let observer = ObserverBox(handler: handler)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(observer).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<ObserverBox>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            kTISNotifyEnabledKeyboardInputSourcesChanged,
            nil,
            .deliverImmediately
        )
        return observer
    }

    private static func lookup(id: String, includeAllInstalled: Bool) -> InputSourceInfo? {
        guard let unmanaged = TISCreateInputSourceList(
            [kTISPropertyInputSourceID: id] as CFDictionary,
            includeAllInstalled
        ) else { return nil }
        let list = unmanaged.takeRetainedValue() as! [TISInputSource]
        return list.compactMap(info(from:)).first
    }

    private static func list(includeAllInstalled: Bool) -> [InputSourceInfo] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any,
            kTISPropertyInputSourceIsSelectCapable: kCFBooleanTrue!,
        ]
        guard let unmanaged = TISCreateInputSourceList(filter as CFDictionary, includeAllInstalled) else {
            return []
        }
        let list = unmanaged.takeRetainedValue() as! [TISInputSource]
        return list.compactMap(info(from:))
    }

    private static func info(from src: TISInputSource) -> InputSourceInfo? {
        guard let id = stringProperty(src, kTISPropertyInputSourceID) else { return nil }
        let name = stringProperty(src, kTISPropertyLocalizedName) ?? id
        guard let data = dataProperty(src, kTISPropertyUnicodeKeyLayoutData), !data.isEmpty else {
            return nil
        }
        return InputSourceInfo(id: id, name: name, layoutData: data)
    }

    private static func stringProperty(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func dataProperty(_ src: TISInputSource, _ key: CFString) -> Data? {
        guard let raw = TISGetInputSourceProperty(src, key) else { return nil }
        let cf = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        return cf as Data
    }
}

private final class ObserverBox: @unchecked Sendable {
    let handler: @Sendable () -> Void
    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
}
