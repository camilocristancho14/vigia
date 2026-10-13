import Foundation
import Testing
@testable import Pulse

/// A turn that waits for a person, and one that failed, read from the same
/// transcripts the working state is.
@Suite("Agent waiting and failure")
struct AgentWaitingTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    @Test("Claude Code: a question or a plan put to the person is waiting, not working")
    func claudeAsksAPerson() throws {
        let home = try EditorTestSupport.temporary("claude-waiting")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: "session.jsonl")
        let at = Self.stamp(Self.now)

        for tool in ["AskUserQuestion", "ExitPlanMode"] {
            try EditorTestSupport.jsonLines([
                ["type": "assistant", "timestamp": at, "message": [
                    "stop_reason": "tool_use",
                    "content": [["type": "tool_use", "name": tool, "input": [:] as [String: Any]]],
                ]],
            ], to: file)
            #expect(AgentActivity.verdict(for: file, provider: .claudeCode) == .waiting(at: Self.now))
        }

        try EditorTestSupport.jsonLines([
            ["type": "assistant", "timestamp": at, "message": [
                "stop_reason": "tool_use",
                "content": [["type": "tool_use", "name": "Bash", "input": [:] as [String: Any]]],
            ]],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .claudeCode) == .working(.tool, at: Self.now))
    }

    @Test("Claude Code: an API error ends the turn as a failure")
    func claudeAPIError() throws {
        let home = try EditorTestSupport.temporary("claude-failed")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: "session.jsonl")
        try EditorTestSupport.jsonLines([
            ["type": "assistant", "timestamp": Self.stamp(Self.now), "isApiErrorMessage": true,
             "message": ["stop_reason": "stop_sequence", "content": [["type": "text", "text": "API Error"]]]],
        ], to: file)
        #expect(AgentActivity.verdict(for: file, provider: .claudeCode) == .failed(at: Self.now))
    }

    @Test("Kiro's pending interaction waits for a person; Grok's failed turn is a failure")
    func kiroAndGrok() throws {
        let home = try EditorTestSupport.temporary("kiro-grok-waiting")
        defer { try? FileManager.default.removeItem(at: home) }
        let kiro = home.appending(path: "messages.jsonl")
        try EditorTestSupport.jsonLines([
            ["timestamp": Self.stamp(Self.now), "payload": ["type": "pending_interaction"]],
        ], to: kiro)
        #expect(AgentActivity.verdict(for: kiro, provider: .kiro) == .waiting(at: Self.now))

        let grok = home.appending(path: "updates.jsonl")
        try EditorTestSupport.jsonLines([
            ["params": ["timestamp": Self.now.timeIntervalSince1970, "update": ["sessionUpdate": "turn_failed"]]],
        ], to: grok)
        #expect(AgentActivity.verdict(for: grok, provider: .grok) == .failed(at: Self.now))
    }

    @Test("States: waiting is not working, and a session that died on the model's move is a failure")
    func statesFromFiles() throws {
        let home = try EditorTestSupport.temporary("claude-states")
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appending(path: ".claude/projects/demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appending(path: "session.jsonl")

        try EditorTestSupport.jsonLines([
            ["type": "assistant", "timestamp": Self.stamp(Self.now.addingTimeInterval(-60)), "message": [
                "stop_reason": "tool_use",
                "content": [["type": "tool_use", "name": "AskUserQuestion"]],
            ]],
        ], to: file)
        try FileManager.default.setAttributes([.modificationDate: Self.now], ofItemAtPath: file.path)
        var state = try #require(AgentActivity.states(for: [.claudeCode], now: Self.now, home: home)[.claudeCode])
        #expect(!state.isWorking && state.isWaiting && state.failedAt == nil)

        // A prompt nobody answered for four minutes: the session died.
        try EditorTestSupport.jsonLines([
            ["type": "user", "timestamp": Self.stamp(Self.now.addingTimeInterval(-240)),
             "message": ["content": "go on"]],
        ], to: file)
        try FileManager.default.setAttributes([.modificationDate: Self.now], ofItemAtPath: file.path)
        state = try #require(AgentActivity.states(for: [.claudeCode], now: Self.now, home: home)[.claudeCode])
        #expect(!state.isWorking && !state.isWaiting)
        #expect(state.failedAt == Self.now.addingTimeInterval(-240 + AgentActivity.Wait.model.grace))
    }
}
