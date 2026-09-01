import Foundation
import LayoutConversion

/// The two slots and the layout maps they point at, kept in step with each
/// other.
///
/// The maps are a cache of what the slots say, so choosing a slot rebuilds them
/// here. Left to its callers, that invalidation was three writes per pick and
/// one of them was easy to forget — a forgotten one leaves conversion running
/// against the layout the user just changed away from.
@MainActor
final class Pair {
    private let settings: SettingsStore
    private let catalog: LayoutCatalog
    private var maps: [String: LayoutMap] = [:]
    private var observer: AnyObject?

    /// What the user can pick between, as of the last rebuild.
    private(set) var enabledLayouts: [InputSourceInfo] = []

    init(settings: SettingsStore, catalog: LayoutCatalog) {
        self.settings = settings
        self.catalog = catalog
        reloadFromSystem()
        observer = catalog.watchChanges { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.reloadFromSystem() } }
        }
    }

    var slotA: String? { settings.slotA }
    var slotB: String? { settings.slotB }
    var ids: (String, String)? { settings.pairIDs() }

    /// Only for the start-up log, where an empty set is the first sign that
    /// nothing will convert.
    var loadedMapCount: Int { maps.count }

    /// The two maps conversion runs between, or nil while the pair is not
    /// ready: no two distinct slots, or a slot whose layout will not load.
    var conversionMaps: (slotA: LayoutMap, slotB: LayoutMap)? {
        guard let ids, let a = maps[ids.0], let b = maps[ids.1] else { return nil }
        return (slotA: a, slotB: b)
    }

    func chooseSlotA(_ id: String) {
        settings.setSlotA(id)
        reloadFromSystem()
    }

    func chooseSlotB(_ id: String) {
        settings.setSlotB(id)
        reloadFromSystem()
    }

    /// Rebuild from what the system reports now — the only way the maps ever
    /// move, so there is one place for them to go stale rather than four.
    func reloadFromSystem() {
        let enabled = catalog.enabledLayouts()
        settings.seedIfNeeded(layouts: enabled)
        enabledLayouts = enabled
        var next: [String: LayoutMap] = [:]
        for info in enabled {
            next[info.id] = catalog.loadMap(for: info)
        }
        // A slot can point at a source the user has since disabled. Keep it
        // usable rather than silently dropping half the pair.
        for id in [settings.slotA, settings.slotB].compactMap({ $0 }) where next[id] == nil {
            next[id] = catalog.findLayout(id: id).flatMap(catalog.loadMap(for:))
        }
        maps = next
    }
}
