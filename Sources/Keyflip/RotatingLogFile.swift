import Foundation

// Owned by the log's serial I/O queue; no event callback performs disk I/O.
final class RotatingLogFile {
    private let handle: FileHandle
    private let limit: Int
    private var bytes = 0

    init(url: URL, limit: Int = 1_048_576) throws {
        self.limit = limit
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        handle = try FileHandle(forWritingTo: url)
        // Older versions logged field contents. Start this launch with redacted diagnostics only.
        try handle.truncate(atOffset: 0)
    }

    deinit { try? handle.close() }

    func append(_ line: String) throws {
        let data = Data((line + "\n").utf8)
        guard data.count <= limit else { return }
        if bytes + data.count > limit {
            try handle.truncate(atOffset: 0)
            try handle.seek(toOffset: 0)
            bytes = 0
        }
        try handle.write(contentsOf: data)
        bytes += data.count
    }
}
