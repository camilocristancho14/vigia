import Foundation
import SQLite3
import Testing
@testable import Pulse

/// `agy` session state, held against excerpts of real CLI logs from
/// 2026-09-23 and the real `conversation_summaries` schema. Confirmation
/// lines are the binary's printf, not a captured log, and are marked as such.
@Suite("agy CLI session")
struct AntigravityCLISessionTests {
    private static let utc = TimeZone(secondsFromGMT: 0)!
    private static let year = 2026

    private static func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func stamp(
        month: Int, day: Int, hour: Int, minute: Int, second: Int, nanosecond: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second, nanosecond: nanosecond
        ))!
    }

    private static func read(
        _ text: String,
        summaries: [AntigravityCLISession.Summary] = [],
        processRunning: Bool,
        now: Date
    ) -> AntigravityCLISession.Reading {
        AntigravityCLISession.reading(
            log: text,
            year: year,
            summaries: summaries,
            processRunning: processRunning,
            now: now,
            timeZone: utc
        )
    }

    @Test("A ready CLI that then lost its terminal is not working, and the bare ready line keeps the previous stamp")
    func readyThenTerminalGone() throws {
        let text = try Self.fixture("agy-ready-gone")
        let now = Self.stamp(month: 9, day: 23, hour: 18, minute: 0, second: 0)
        let gone = Self.stamp(month: 9, day: 23, hour: 14, minute: 5, second: 6, nanosecond: 347_739_000)
        let ready = Self.stamp(month: 9, day: 23, hour: 11, minute: 58, second: 16, nanosecond: 600_341_000)

        let closed = Self.read(text, processRunning: true, now: now)
        #expect(closed.sessionEnded)
        #expect(!closed.isWorking && !closed.isWaiting)
        #expect(closed.lastWrite == gone)
        #expect(closed.httpsPort == 35523)
        #expect(closed.httpPort == 34935)
        #expect(closed.ports == [35523, 34935])

        let startup = text.split(separator: "\n").filter { !$0.contains("Terminal gone") }.joined(separator: "\n")
        let open = Self.read(startup, processRunning: true, now: now)
        #expect(!open.sessionEnded)
        #expect(!open.isWorking && !open.isWaiting)
        #expect(open.lastWrite == now)

        let left = Self.read(startup, processRunning: false, now: now)
        #expect(!left.isWorking)
        #expect(left.lastWrite == ready)
    }

    @Test("Print mode is work only while that process is still running")
    func printMode() throws {
        let text = try Self.fixture("agy-print-mode")
        let now = Self.stamp(month: 9, day: 23, hour: 12, minute: 0, second: 0)
        let started = Self.stamp(month: 9, day: 23, hour: 11, minute: 56, second: 36, nanosecond: 584_609_000)

        let running = Self.read(text, processRunning: true, now: now)
        #expect(running.isWorking)
        #expect(running.label == "Thinking…")
        #expect(!running.isWaiting)
        #expect(running.httpsPort == 44935)
        #expect(running.httpPort == 37347)
        #expect(!running.sessionEnded)

        let stopped = Self.read(text, processRunning: false, now: now)
        #expect(!stopped.isWorking)
        #expect(stopped.lastWrite == started)
    }

    @Test("The latest decisive line wins: ready, then print mode, is work")
    func laterPrintModeBeatsReady() throws {
        let text = """
        I0923 11:58:16.600341       1 common.go:435] Starting CLI program
        CLI ready for user input
        I0923 12:01:00.000000       1 printmode.go:181] Print mode: starting (promptLength=4, model="", conversationID="")
        """
        let now = Self.stamp(month: 9, day: 23, hour: 12, minute: 5, second: 0)
        let running = Self.read(text, processRunning: true, now: now)
        #expect(running.isWorking)
        #expect(running.label == "Thinking…")

        let back = text + "\nCLI ready for user input\n"
        let idle = Self.read(back, processRunning: true, now: now)
        #expect(!idle.isWorking && !idle.isWaiting)
        #expect(idle.lastWrite == now)
    }

    @Test("A quota reload is not a turn")
    func quotaReloadIsNotWork() {
        let text = """
        I0923 11:58:16.579451     195 quota_manager.go:36] doRefreshQuota: skipped (not logged in)
        I0923 12:01:10.277247     195 quota_manager.go:45] doRefreshQuota: starting reload (force=true)
        """
        let now = Self.stamp(month: 9, day: 23, hour: 12, minute: 2, second: 0)
        let reading = Self.read(text, processRunning: true, now: now)
        #expect(!reading.isWorking && !reading.isWaiting)
        #expect(reading.lastWrite == now)
    }

    @Test("Tool confirmation waits; a later clear, ready line, or shutdown settles it")
    func toolConfirmation() throws {
        let text = try Self.fixture("agy-tool-confirmation")
        let asked = Self.stamp(month: 9, day: 23, hour: 12, minute: 10, second: 0, nanosecond: 100_000_000)
        let soon = asked.addingTimeInterval(10 * 60)
        let later = asked.addingTimeInterval(31 * 60)

        let waiting = Self.read(text, processRunning: true, now: soon)
        #expect(waiting.isWaiting && !waiting.isWorking)
        #expect(waiting.lastWrite == soon)

        let still = Self.read(text, processRunning: false, now: soon)
        #expect(still.isWaiting && !still.isWorking)

        let expired = Self.read(text, processRunning: false, now: later)
        #expect(!expired.isWaiting && !expired.isWorking)
        #expect(expired.lastWrite == asked)

        let cleared = text + "\nI0923 12:11:00.000000       1 binary:0] user cleared pending tool confirmation: \"example\"\n"
        let working = Self.read(cleared, processRunning: true, now: soon)
        #expect(working.isWorking && !working.isWaiting)
        #expect(working.label == "Thinking…")
        let clearedGone = Self.read(cleared, processRunning: false, now: soon)
        #expect(!clearedGone.isWorking && !clearedGone.isWaiting)

        let ready = text + "\nCLI ready for user input\n"
        let idle = Self.read(ready, processRunning: true, now: soon)
        #expect(!idle.isWaiting && !idle.isWorking)

        let gone = text + "\nI0923 12:12:00.000000       1 common.go:385] Terminal gone, shutting down\n"
        let shut = Self.read(gone, processRunning: true, now: soon)
        #expect(shut.sessionEnded)
        #expect(!shut.isWaiting && !shut.isWorking)
    }

    @Test("not_fully_idle is a turn in flight; killed is not, and a later shutdown wins")
    func summaryFlag() throws {
        let startup = try Self.fixture("agy-ready-gone")
            .split(separator: "\n")
            .filter { !$0.contains("Terminal gone") }
            .joined(separator: "\n")
        let now = Self.stamp(month: 9, day: 23, hour: 12, minute: 31, second: 0)
        let busy = AntigravityCLISession.Summary(
            notFullyIdle: true,
            killed: false,
            lastModified: Self.stamp(month: 9, day: 23, hour: 12, minute: 30, second: 0)
        )
        let running = Self.read(startup, summaries: [busy], processRunning: true, now: now)
        #expect(running.isWorking)
        #expect(running.label == "Thinking…")

        let killed = AntigravityCLISession.Summary(
            notFullyIdle: true, killed: true, lastModified: busy.lastModified
        )
        let idle = Self.read(startup, summaries: [killed], processRunning: true, now: now)
        #expect(!idle.isWorking)
        #expect(idle.lastWrite == now)

        let crashed = Self.read(startup, summaries: [busy], processRunning: false, now: now)
        #expect(crashed.isWorking)

        let stale = Self.read(
            startup,
            summaries: [busy],
            processRunning: false,
            now: busy.lastModified!.addingTimeInterval(AgentActivity.Wait.tool.grace + 1)
        )
        #expect(!stale.isWorking)

        let shut = try Self.fixture("agy-ready-gone")
        let after = Self.read(shut, summaries: [busy], processRunning: true, now: now)
        #expect(after.sessionEnded)
        #expect(!after.isWorking)
    }

    @Test("The executable is agy itself, not a command line that mentions it")
    func processIdentity() {
        #expect(AntigravityCLISession.commandNamesAgy(["9", "/home/user/.local/bin/agy"]))
        #expect(AntigravityCLISession.commandNamesAgy(["9", "agy", "--print", "hi"]))
        #expect(!AntigravityCLISession.commandNamesAgy(["9", "/usr/bin/grok", "--prompt", "track agy"]))
        #expect(!AntigravityCLISession.commandNamesAgy(["9", "/usr/bin/agy-helper"]))
        #expect(AntigravityCLISession.csrfToken(in: ["9", "/bin/agy"]) == nil)
        #expect(AntigravityCLISession.csrfToken(in: ["9", "/bin/agy", "--csrf_token", "not-a-real-token"]) == "not-a-real-token")
        #expect(AntigravityCLISession.year(in: "cli-20260923_115816.log") == 2026)
    }

    @Test("Antigravity joins the local activity scan without pretending the JSONL ledger can read it")
    func activityFlag() {
        #expect(Provider.antigravity.supportsLocalActivity)
        #expect(!Provider.antigravity.keepsLocalTranscripts)
        let route = Provider.antigravity.soleRoute
        #expect(route?.name.contains("agy") == true)
        #expect(route?.note.contains("agy") == true)
    }

    @Test("states() reads the fixture home and the injected process check")
    func wiredIntoActivity() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "agy-activity-\(UUID().uuidString)")
        let log = home.appending(path: ".gemini/antigravity-cli/log/cli-20260923_115816.log")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data(Self.fixture("agy-ready-gone").utf8).write(to: log)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let shut = try #require(
            AgentActivity.states(for: [.antigravity], now: now, home: home, agyRunning: { true })[.antigravity]
        )
        #expect(!shut.isWorking && !shut.isWaiting)
        #expect(shut.lastWrite != now)
        #expect(shut.lastWrite != nil)

        let empty = FileManager.default.temporaryDirectory.appending(path: "agy-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let asleep = try #require(
            AgentActivity.states(for: [.antigravity], now: now, home: empty, agyRunning: { false })[.antigravity]
        )
        #expect(!asleep.isWorking && asleep.lastWrite == nil)
        let awake = try #require(
            AgentActivity.states(for: [.antigravity], now: now, home: empty, agyRunning: { true })[.antigravity]
        )
        #expect(!awake.isWorking && awake.lastWrite == now)
    }

    @Test("Live log ports come from a session that has not shut down")
    func liveLogPorts() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "agy-ports-\(UUID().uuidString)")
        let directory = home.appending(path: ".gemini/antigravity-cli/log")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let older = directory.appending(path: "cli-20260923_115636.log")
        try Data(Self.fixture("agy-print-mode").utf8).write(to: older)
        #expect(AntigravityCLISession.liveLogPorts(home: home) == [44935, 37347])

        let newer = directory.appending(path: "cli-20260923_115816.log")
        try Data(Self.fixture("agy-ready-gone").utf8).write(to: newer)
        #expect(AntigravityCLISession.liveLogPorts(home: home).isEmpty)
    }

    @Test("A real summary row with not_fully_idle overrides an earlier ready line")
    func summaryDatabase() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "agy-db-\(UUID().uuidString)")
        let log = home.appending(path: ".gemini/antigravity-cli/log/cli-20260923_115644.log")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let startup = try Self.fixture("agy-ready-gone")
            .split(separator: "\n")
            .filter { !$0.contains("Terminal gone") }
            .joined(separator: "\n")
        try Data(startup.utf8).write(to: log)

        let database = home.appending(path: ".gemini/antigravity-cli/conversation_summaries.db")
        try Self.sqlite(at: database, [
            Self.summarySchema,
            """
            INSERT INTO conversation_summaries (
                conversation_id, workspace_uris, last_modified_time, last_user_input_time,
                not_fully_idle, killed
            ) VALUES (
                'conv-test', '[]', '2026-09-23 12:30:00', '2026-09-23 12:29:00',
                1, 0
            )
            """,
        ])

        let now = Self.stamp(month: 9, day: 23, hour: 12, minute: 31, second: 0)
        let state = AntigravityCLISession.state(home: home, processRunning: true, now: now, timeZone: Self.utc)
        #expect(state.isWorking)
        #expect(state.label == "Thinking…")
        #expect(!state.isWaiting)
    }

    /// The table as `agy` 1.2.9 created it. Rows in tests are synthetic.
    private static let summarySchema = """
        CREATE TABLE conversation_summaries (
            conversation_id text,
            title text NOT NULL DEFAULT "",
            preview text NOT NULL DEFAULT "",
            step_count integer NOT NULL DEFAULT 0,
            last_modified_time datetime NOT NULL,
            workspace_uris text NOT NULL,
            status text NOT NULL DEFAULT "",
            source text NOT NULL DEFAULT "",
            project_id text NOT NULL DEFAULT "",
            agent_name text NOT NULL DEFAULT "",
            parent_conversation_id text NOT NULL DEFAULT "",
            nesting_depth integer NOT NULL DEFAULT 0,
            battle_id text NOT NULL DEFAULT "",
            winning_conversation_id text NOT NULL DEFAULT "",
            not_fully_idle numeric NOT NULL DEFAULT false,
            killed numeric NOT NULL DEFAULT false,
            last_user_input_time datetime NOT NULL,
            last_user_input_step_index integer NOT NULL DEFAULT -1,
            app_data_dir text NOT NULL DEFAULT "",
            raw_summary blob,
            group_id text NOT NULL DEFAULT "",
            PRIMARY KEY (conversation_id)
        )
        """

    private static func sqlite(at url: URL, _ statements: [String]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        for statement in statements {
            let result = sqlite3_exec(handle, statement, nil, nil, nil)
            #expect(result == SQLITE_OK)
        }
    }
}
