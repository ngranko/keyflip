import Foundation
import Testing
@testable import Keyflip

@Test func logRotationBoundsDiskUsageDuringTheSameLaunch() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let log = try RotatingLogFile(url: url, limit: 12)
    try log.append("first")
    try log.append("next")
    #expect(try String(contentsOf: url, encoding: .utf8) == "first\nnext\n")
    try log.append("last")
    #expect(try String(contentsOf: url, encoding: .utf8) == "last\n")
    try log.append(String(repeating: "x", count: 13))
    #expect(try Data(contentsOf: url).count == 5)
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
}
