import Foundation
import Testing
@testable import Pulse

@Suite("Background Claude Code sessions")
struct BackgroundSessionTests {
    @Test("A plugin's observer session is not the user's Claude Code")
    func observer() {
        let base = "/Users/me/.claude/projects"
        #expect(AgentActivity.isBackgroundSession(URL(fileURLWithPath:
            "\(base)/-Users-me--claude-mem-observer-sessions/abc.jsonl")))
        #expect(AgentActivity.isBackgroundSession(URL(fileURLWithPath:
            "\(base)/-Users-me--claude-mem-observer-sessions/abc/subagents/agent-1.jsonl")))
        #expect(!AgentActivity.isBackgroundSession(URL(fileURLWithPath:
            "\(base)/-Users-me-Documents-GitHub-vigia/abc.jsonl")))
    }

    @Test("A background session failing on every call does not make Clawd fail")
    func failuresIgnored() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appending(path: ".claude/projects/-Users-me--claude-mem-observer-sessions")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let record = #"{"type":"assistant","isApiErrorMessage":true,"timestamp":"\#(stamp)","message":{"role":"assistant","stop_reason":"stop_sequence","content":[{"type":"text","text":"Prompt is too long"}]}}"#
        try Data((record + "\n").utf8).write(to: folder.appending(path: "s.jsonl"))

        let state = AgentActivity.states(for: [.claudeCode], home: home)[.claudeCode]
        #expect(state?.failedAt == nil)
        #expect(state?.isWorking != true)
    }
}
