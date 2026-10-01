// Modified for Vigía from Pulse (Apache-2.0).
// Activity probes for agents whose sessions are not the JSONL shape Pulse
// already reads. Cursor's logic follows codenotch (MIT); Gemini CLI follows
// its recency check. Grok Build is read in AgentActivity.
import Foundation

enum VigiaActivity {
    static let cursorStale: TimeInterval = 45
    static let geminiStale: TimeInterval = 45

    /// True when Cursor is open and a non-subagent composer still has an
    /// unfinished run whose checkpoint moved recently.
    static func cursorIsWorking(
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        now: Date = Date()
    ) -> Bool {
        guard cursorProcessRunning() else { return false }
        let database = home.appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: database.path) else { return false }
        var working = false
        _ = AgentSQLite.read(at: database) { handle in
            AgentSQLite.each(
                handle,
                sql: """
                SELECT value, isSubagent FROM composerHeaders \
                WHERE isArchived = 0 ORDER BY recency DESC LIMIT 40
                """
            ) { statement in
                if working { return }
                if AgentSQLite.text(statement, column: 1) == "1" { return }
                guard
                    let json = AgentSQLite.text(statement, column: 0),
                    let data = json.data(using: .utf8),
                    let header = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }
                if (header["isSubagent"] as? Bool) == true { return }
                guard unixDate(header["unfinishedRunAt"]) != nil else { return }
                let stamp = unixDate(header["conversationCheckpointLastUpdatedAt"])
                    ?? unixDate(header["lastUpdatedAt"])
                    ?? unixDate(header["unfinishedRunAt"])
                guard let stamp, now.timeIntervalSince(stamp) <= cursorStale else { return }
                working = true
            }
        }
        return working
    }

    /// Modification date of the newest Gemini CLI transcript, if any.
    static func geminiLatestWrite(home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> Date? {
        let root = home.appending(path: ".gemini")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var newest: Date?
        var seen = 0
        for case let url as URL in walker {
            if seen >= 4_000 { break }
            let ext = url.pathExtension.lowercased()
            guard ext == "json" || ext == "jsonl" else { continue }
            seen += 1
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { continue }
            if newest == nil || modified > newest! { newest = modified }
        }
        return newest
    }

    /// Process name, not AppKit: this runs on the activity queue.
    private static func cursorProcessRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "Cursor"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func unixDate(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw > 1_000_000_000 else { return nil }
        let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }
}
