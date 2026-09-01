import Foundation
import LayoutConversion
import Testing
@testable import Keyflip

/// The second adapter behind `LayoutCatalog`. The real Text Input Source APIs
/// cannot be called from a parallel test run without aborting, which is why
/// this seam earns its keep.
final class ScriptedCatalog: LayoutCatalog {
    var enabled: [InputSourceInfo]
    /// Installed but switched off — where a slot the user disabled is found.
    var installed: [InputSourceInfo]
    var unloadable: Set<String> = []
    private(set) var watching = false

    init(enabled: [String], installed: [String] = []) {
        self.enabled = enabled.map(Self.info)
        self.installed = installed.map(Self.info)
    }

    private static func info(_ id: String) -> InputSourceInfo {
        InputSourceInfo(id: id, name: id, layoutData: Data())
    }

    func enabledLayouts() -> [InputSourceInfo] { enabled }

    func loadMap(for info: InputSourceInfo) -> LayoutMap? {
        guard !unloadable.contains(info.id) else { return nil }
        return LayoutMap(id: info.id, name: info.name, reverse: [:], forward: [:])
    }

    func findLayout(id: String) -> InputSourceInfo? {
        (enabled + installed).first { $0.id == id }
    }

    func watchChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        watching = true
        return NSObject()
    }
}

private let abc = "com.apple.keylayout.ABC"
private let rus = "com.apple.keylayout.RussianWin"
private let us = "com.apple.keylayout.US"

@MainActor
private func store(slotA: String? = nil, slotB: String? = nil) -> SettingsStore {
    let defaults = UserDefaults(suiteName: "KeyflipPairTests")!
    defaults.removePersistentDomain(forName: "KeyflipPairTests")
    let settings = SettingsStore(defaults: defaults)
    settings.slotA = slotA
    settings.slotB = slotB
    return settings
}

@MainActor
@Test func aPairOfLoadableSlotsIsReadyToConvert() {
    let catalog = ScriptedCatalog(enabled: [abc, rus])
    let pair = Pair(settings: store(slotA: abc, slotB: rus), catalog: catalog)
    #expect(pair.conversionMaps?.slotA.id == abc)
    #expect(pair.conversionMaps?.slotB.id == rus)
}

@Test @MainActor func aSlotWhoseLayoutWillNotLoadIsNotReady() {
    let catalog = ScriptedCatalog(enabled: [abc, rus])
    catalog.unloadable = [rus]
    let pair = Pair(settings: store(slotA: abc, slotB: rus), catalog: catalog)
    #expect(pair.conversionMaps == nil)
}

/// Two slots pointing at one layout is not a pair, so the seed repairs it
/// rather than leaving the trigger dead.
@Test @MainActor func twoSlotsPointingAtTheSameLayoutAreReseeded() {
    let settings = store(slotA: abc, slotB: abc)
    let pair = Pair(settings: settings, catalog: ScriptedCatalog(enabled: [abc, rus]))
    #expect(settings.slotB == rus)
    #expect(pair.conversionMaps?.slotB.id == rus)
}

/// The whole point of the module: the maps are a cache of the slots, so
/// choosing one rebuilds them. Left to the caller this was a separate write,
/// and forgetting it left conversion running against the old layout.
@Test @MainActor func choosingASlotRebuildsTheMaps() {
    let pair = Pair(
        settings: store(slotA: abc, slotB: rus),
        catalog: ScriptedCatalog(enabled: [abc, rus], installed: [us])
    )
    pair.chooseSlotA(us)
    #expect(pair.conversionMaps?.slotA.id == us)
    #expect(pair.conversionMaps?.slotB.id == rus)
}

/// A slot can point at a source the user has since switched off. Keep it
/// usable rather than silently dropping half the pair.
@Test @MainActor func aSlotTheUserDisabledIsStillLoaded() {
    let pair = Pair(
        settings: store(slotA: us, slotB: rus),
        catalog: ScriptedCatalog(enabled: [abc, rus], installed: [us])
    )
    #expect(pair.conversionMaps?.slotA.id == us)
}

@Test @MainActor func anEmptyPairSeedsLatinAndCyrillicWhenBothAreThere() {
    let settings = store()
    let pair = Pair(settings: settings, catalog: ScriptedCatalog(enabled: [us, abc, rus]))
    #expect(settings.slotA == abc)
    #expect(settings.slotB == rus)
    #expect(pair.conversionMaps != nil)
}

@Test @MainActor func anEmptyPairFallsBackToTheFirstTwoEnabledLayouts() {
    let settings = store()
    let german = "com.apple.keylayout.German"
    _ = Pair(settings: settings, catalog: ScriptedCatalog(enabled: [us, german]))
    #expect(settings.slotA == us)
    #expect(settings.slotB == german)
}

@Test @MainActor func aSingleEnabledLayoutSeedsNothing() {
    let settings = store()
    let pair = Pair(settings: settings, catalog: ScriptedCatalog(enabled: [us]))
    #expect(settings.slotA == nil)
    #expect(pair.conversionMaps == nil)
}

@Test @MainActor func thePairWatchesForLayoutsBeingEnabledOrRemoved() {
    let catalog = ScriptedCatalog(enabled: [abc, rus])
    _ = Pair(settings: store(slotA: abc, slotB: rus), catalog: catalog)
    #expect(catalog.watching)
}

@Test @MainActor func reloadingPicksUpALayoutEnabledSinceLaunch() {
    let catalog = ScriptedCatalog(enabled: [abc, rus])
    let pair = Pair(settings: store(slotA: abc, slotB: rus), catalog: catalog)
    #expect(pair.enabledLayouts.count == 2)
    catalog.enabled.append(InputSourceInfo(id: us, name: us, layoutData: Data()))
    pair.reloadFromSystem()
    #expect(pair.enabledLayouts.count == 3)
}
