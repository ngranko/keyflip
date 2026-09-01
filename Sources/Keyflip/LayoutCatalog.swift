import Foundation
import LayoutConversion

/// The keyboard layouts the system offers, and notice when that set changes.
///
/// Two adapters: the Text Input Source APIs in the app, a written-down list in
/// tests — where those APIs cannot be called at all without aborting under
/// parallel test runs.
protocol LayoutCatalog {
    func enabledLayouts() -> [InputSourceInfo]
    func loadMap(for info: InputSourceInfo) -> LayoutMap?
    func findLayout(id: String) -> InputSourceInfo?
    func watchChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject
}

struct SystemLayouts: LayoutCatalog {
    func enabledLayouts() -> [InputSourceInfo] {
        InputSources.enabledKeyboardLayouts()
    }

    func loadMap(for info: InputSourceInfo) -> LayoutMap? {
        InputSources.map(for: info)
    }

    func findLayout(id: String) -> InputSourceInfo? {
        InputSources.layout(id: id)
    }

    func watchChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        InputSources.observeEnabledChanges(handler)
    }
}
