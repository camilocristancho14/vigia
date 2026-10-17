import Foundation
import Testing
@testable import Pulse

/// The status line capture moved from `pulse-usage.json` to
/// `vigia-usage.json`. Both are read; the newer one wins. Temporary files only.
@Suite("Status line capture files")
struct StatusLineCaptureTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "VigiaStatusLine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func capture(_ name: String, at time: Double?, percent: Int) throws -> URL {
        var payload: [String: Any] = ["rate_limits": ["five_hour": ["used_percentage": percent]]]
        if let time { payload["capturedAt"] = time }
        let file = root.appending(path: name)
        try JSONSerialization.data(withJSONObject: payload).write(to: file)
        return file
    }

    private func percent(_ capture: [String: Any]?) -> Int? {
        ((capture?["rate_limits"] as? [String: Any])?["five_hour"] as? [String: Any])?["used_percentage"] as? Int
    }

    @Test("Vigía writes vigia-usage.json and still reads pulse-usage.json")
    func names() {
        #expect(StatusLineHook.cacheFile.lastPathComponent == "vigia-usage.json")
        #expect(StatusLineHook.cacheFiles.map(\.lastPathComponent) == ["vigia-usage.json", "pulse-usage.json"])
        #expect(StatusLineHook.backupExtensions == ["vigia-backup", "pulse-backup"])
    }

    @Test("Only the old file: it is read")
    func legacyOnly() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = try capture("pulse-usage.json", at: 100, percent: 40)
        let service = ClaudeCodeUsageService(cacheFiles: [root.appending(path: "vigia-usage.json"), legacy])
        #expect(percent(service.newestCapture()) == 40)
    }

    @Test("Both files: the newer capture wins, whichever name it has")
    func newestWins() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let current = try capture("vigia-usage.json", at: 200, percent: 70)
        let legacy = try capture("pulse-usage.json", at: 100, percent: 40)
        #expect(percent(ClaudeCodeUsageService(cacheFiles: [current, legacy]).newestCapture()) == 70)

        let newerLegacy = try capture("pulse-usage.json", at: 300, percent: 90)
        #expect(percent(ClaudeCodeUsageService(cacheFiles: [current, newerLegacy]).newestCapture()) == 90)
    }

    @Test("Undated captures fall back to the order given, Vigía's first")
    func undated() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let current = try capture("vigia-usage.json", at: nil, percent: 10)
        let legacy = try capture("pulse-usage.json", at: nil, percent: 20)
        #expect(percent(ClaudeCodeUsageService(cacheFiles: [current, legacy]).newestCapture()) == 10)
        #expect(ClaudeCodeUsageService(cacheFiles: [root.appending(path: "none.json")]).newestCapture() == nil)
    }
}
