import Foundation
import Testing
@testable import Pulse

@Suite("Waiting on a long command")
struct CommandWaitTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// The shared table, which `scripts/test-vigia-notify.sh` also checks the
    /// hook against.
    static func table() throws -> [(kind: CommandKind?, command: String)] {
        let url = try #require(Bundle.module.url(forResource: "command-kinds", withExtension: "tsv",
                                                 subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.hasPrefix("#") && $0.contains("\t") }
            .map { line in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                return (CommandKind(rawValue: parts[0]), parts[1])
            }
    }

    @Test("Every command in the shared table is classified as the table says")
    func sharedTable() throws {
        let table = try Self.table()
        #expect(table.count > 60)
        for row in table {
            #expect(CommandWait.kind(of: row.command) == row.kind, "\(row.command)")
        }
    }

    @Test("A compound command counts as its slowest part")
    func compound() {
        #expect(CommandWait.kind(of: "swift build && swift test") == .test)
        #expect(CommandWait.kind(of: "git pull; make") == .build)
        #expect(CommandWait.kind(of: "pytest 2>&1 | tee /tmp/out.txt") == .test)
        #expect(CommandWait.kind(of: "") == nil)
    }

    @Test("A hook names the kind loosely, and an old hook names none")
    func kindNames() {
        #expect(CommandKind(named: "test") == .test)
        #expect(CommandKind(named: " Build ") == .build)
        #expect(CommandKind(named: nil) == nil)
        #expect(CommandKind(named: "") == nil)
        #expect(CommandKind(named: "deploy") == nil)
    }

    @Test("Tests and builds are named at once; any other command after twenty seconds")
    func labels() {
        let label = { (tool: String, kind: CommandKind?, running: TimeInterval) in
            CommandWait.label(tool: tool, kind: kind, running: running, toolLabel: AgentActivity.toolLabel)
        }
        #expect(label("Bash", .test, 0) == "Testing…")
        #expect(label("Bash", .build, 1) == "Building…")
        #expect(label("Bash", nil, 5) == "Running command")
        #expect(label("Bash", nil, 19.9) == "Running command")
        #expect(label("Bash", nil, 20) == "Waiting on command…")
        // Not a shell: named by the tool, however long it takes.
        #expect(label("Read", .test, 60) == "Reading")
        #expect(label("WebFetch", nil, 60) == "Browsing web")
        #expect(CommandWait.isWait("Testing…") && CommandWait.isWait("Waiting on command…"))
        #expect(!CommandWait.isWait("Running command") && !CommandWait.isWait(nil))
    }

    @Test("Each wait has a pose of its own, and none of them is work")
    func poses() {
        #expect(MascotPose.working(label: "Testing…") == .testing)
        #expect(MascotPose.working(label: "Building…") == .longCommand)
        #expect(MascotPose.working(label: "Waiting on command…") == .longCommand)
        #expect(MascotPose.working(label: "Running command") == .type)
        #expect(!MascotPose.testing.isWorking && !MascotPose.longCommand.isWorking)
    }

    @Test("Working, then testing, then thinking again: the pose follows, and the timer counts the tests alone")
    @MainActor
    func storeTransition() {
        let now = Date()
        let turn = now.addingTimeInterval(-300), tests = now.addingTimeInterval(-75)
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.claudeCode.rawValue]), activity: monitor)

        monitor.adoptDemo(running: [.claudeCode], labels: [.claudeCode: "Editing"], startedAt: [.claudeCode: turn])
        #expect(store.mascotPose(.claudeCode, now: now) == .type)
        #expect(store.timerSince(.claudeCode) == turn)

        monitor.adoptDemo(running: [.claudeCode], labels: [.claudeCode: "Testing…"],
                          startedAt: [.claudeCode: turn], commandSince: [.claudeCode: tests])
        #expect(store.isRunning(.claudeCode))
        #expect(store.mascotPose(.claudeCode, now: now) == .testing)
        #expect(store.timerSince(.claudeCode) == tests)

        monitor.adoptDemo(running: [.claudeCode], labels: [.claudeCode: "Waiting on command…"],
                          startedAt: [.claudeCode: turn], commandSince: [.claudeCode: tests])
        #expect(store.mascotPose(.claudeCode, now: now) == .longCommand)

        // The result is back: thinking, timed from the turn again.
        monitor.adoptDemo(running: [.claudeCode], labels: [.claudeCode: "Thinking…"], startedAt: [.claudeCode: turn])
        #expect(store.mascotPose(.claudeCode, now: now) == .thinking)
        #expect(store.timerSince(.claudeCode) == turn)
    }

    // MARK: - From a hook

    @Test("A remote test run shows at once, outlives the ordinary tool grace, and ends with the call")
    func remoteTest() {
        var ledger = RemoteActivityLedger()
        ledger.record(source: "box", event: "PreToolUse", tool: "Bash", kind: "test", at: t0)
        let early = ledger.state(now: t0.addingTimeInterval(1))
        #expect(early?.label == "Testing…")
        #expect(early?.since == t0)
        // Past the five minutes a plain tool call gets, a test run still runs.
        #expect(ledger.state(now: t0.addingTimeInterval(9 * 60))?.label == "Testing…")
        #expect(ledger.state(now: t0.addingTimeInterval(16 * 60)) == nil)

        // The result comes back: the model's move again.
        ledger.record(source: "box", event: "PostToolUse", tool: "Bash", at: t0.addingTimeInterval(200))
        let after = ledger.state(now: t0.addingTimeInterval(201))
        #expect(after?.label == "Thinking…")
        #expect(after?.since == nil)
    }

    @Test("A remote command with no kind becomes a wait after twenty seconds, and Stop ends it")
    func remotePlainCommand() {
        var ledger = RemoteActivityLedger()
        ledger.record(source: "box", event: "PreToolUse", tool: "Bash", at: t0)
        #expect(ledger.state(now: t0.addingTimeInterval(10))?.label == "Running command")
        #expect(ledger.state(now: t0.addingTimeInterval(25))?.label == "Waiting on command…")
        #expect(ledger.state(now: t0.addingTimeInterval(25))?.since == t0)
        // Its grace is still the ordinary one.
        #expect(ledger.state(now: t0.addingTimeInterval(301)) == nil)

        ledger.record(source: "box", event: "PreToolUse", tool: "Bash", kind: "build", at: t0)
        #expect(ledger.state(now: t0.addingTimeInterval(2))?.label == "Building…")
        ledger.record(source: "box", event: "Stop", tool: nil, at: t0.addingTimeInterval(3))
        #expect(ledger.state(now: t0.addingTimeInterval(4)) == nil)
    }

    @Test("A kind on anything but a shell, or one nobody knows, changes nothing")
    func remoteKindIgnored() {
        var ledger = RemoteActivityLedger()
        ledger.record(source: "box", event: "PreToolUse", tool: "Read", kind: "test", at: t0)
        #expect(ledger.state(now: t0.addingTimeInterval(30))?.label == "Reading")
        ledger.record(source: "box", event: "PreToolUse", tool: "Bash", kind: "deploy", at: t0)
        #expect(ledger.state(now: t0.addingTimeInterval(5))?.label == "Running command")
    }

    // MARK: - From a transcript on this Mac

    private func transcript(_ command: String, at stamp: Date) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "commandwait-\(UUID().uuidString)")
        let project = directory.appending(path: ".claude/projects/demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let url = project.appending(path: "session.jsonl")
        let call: [String: Any] = [
            "type": "assistant",
            "timestamp": ISO8601DateFormatter().string(from: stamp),
            "message": [
                "stop_reason": "tool_use",
                "content": [["type": "tool_use", "name": "Bash", "input": ["command": command]]]
            ]
        ]
        var data = try JSONSerialization.data(withJSONObject: call)
        data.append(0x0A)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        return directory
    }

    @Test("A test run in a local transcript is Testing, timed from its own call, past five minutes")
    func localTest() throws {
        let start = Date().addingTimeInterval(-7 * 60)
        let home = try transcript("python manage.py test --keepdb", at: start)
        defer { try? FileManager.default.removeItem(at: home) }
        let state = AgentActivity.states(for: [.claudeCode], now: Date(), home: home)[.claudeCode]
        #expect(state?.isWorking == true)
        #expect(state?.label == "Testing…")
        #expect(abs((state?.commandSince ?? .distantPast).timeIntervalSince(start)) < 1)
    }

    @Test("A plain command in a local transcript turns into a wait, and lapses at the ordinary grace")
    func localPlainCommand() throws {
        let home = try transcript("sleep 60", at: Date().addingTimeInterval(-30))
        defer { try? FileManager.default.removeItem(at: home) }
        let state = AgentActivity.states(for: [.claudeCode], now: Date(), home: home)[.claudeCode]
        #expect(state?.label == "Waiting on command…")

        let old = try transcript("sleep 600", at: Date().addingTimeInterval(-6 * 60))
        defer { try? FileManager.default.removeItem(at: old) }
        #expect(AgentActivity.states(for: [.claudeCode], now: Date(), home: old)[.claudeCode]?.isWorking == false)
    }
}
