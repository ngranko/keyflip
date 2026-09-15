import Foundation

@MainActor
final class WriteRefusals {
    private struct Entry {
        let handle: FieldHandle
        var failures: Int
        var expires: TimeInterval
    }
    private var entries: [Entry] = []
    private let now: () -> TimeInterval
    private let lifetime: TimeInterval

    init(lifetime: TimeInterval = 600, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.lifetime = lifetime
        self.now = now
    }

    func shouldSkip(_ snapshot: FieldSnapshot) -> Bool {
        expire()
        return entries.contains { $0.handle.matches(snapshot.handle) && $0.failures >= 2 }
    }

    func noteFailure(_ snapshot: FieldSnapshot) {
        expire()
        if let index = entries.firstIndex(where: { $0.handle.matches(snapshot.handle) }) {
            entries[index].failures += 1
            entries[index].expires = now() + lifetime
        } else {
            if entries.count >= 128 { entries.removeFirst() }
            entries.append(Entry(handle: snapshot.handle, failures: 1, expires: now() + lifetime))
        }
    }

    func noteSuccess(_ snapshot: FieldSnapshot) {
        entries.removeAll { $0.handle.matches(snapshot.handle) }
    }

    private func expire() { entries.removeAll { $0.expires <= now() } }
}
