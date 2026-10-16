import Foundation
import Testing
@testable import Pulse

@Suite("Activity labels")
struct ActivityLabelTests {
    @Test("Tools are worded like claude-status-bar")
    func toolWording() {
        #expect(AgentActivity.toolLabel("Bash") == "Running command")
        #expect(AgentActivity.toolLabel("MultiEdit") == "Editing")
        #expect(AgentActivity.toolLabel("Grep") == "Searching")
        #expect(AgentActivity.toolLabel("WebSearch") == "Searching web")
        #expect(AgentActivity.toolLabel("SomethingNew") == "Using tool")
    }

    @Test("A turn waiting on the model is Thinking, one in a tool is named by the tool")
    func transcriptLabel() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "label-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let record = #"{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"text","text":"x"},{"type":"tool_use","name":"Read"}]}}"#
        try (record + "\n").write(to: url, atomically: true, encoding: .utf8)

        #expect(AgentActivity.activityLabel(for: url, provider: .claudeCode, wait: .tool) == "Reading")
        #expect(AgentActivity.activityLabel(for: url, provider: .claudeCode, wait: .model) == "Thinking…")
        #expect(AgentActivity.activityLabel(for: url, provider: .codex, wait: .tool) == "Using tool")
    }

    @Test("Grok names the tool from _meta and a finished tool update is the model's move")
    func grokToolNames() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "grok-label-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: home) }
        // Shape taken from a real updates.jsonl: name is under _meta, the
        // command is rawInput.command, and a completed update carries status
        // but not the name. Values here are stand-ins; title is omitted
        // because it is a path or the raw command.
        let call = """
        {"params":{"timestamp":1800000000,"update":{"sessionUpdate":"tool_call","toolCallId":"call-1","rawInput":{"target_file":"Notes.txt"},"_meta":{"x.ai/tool":{"name":"read_file","kind":"read"}}}}}
        """
        try (call + "\n").write(to: home, atomically: true, encoding: .utf8)
        #expect(AgentActivity.verdict(for: home, provider: .grok) == .working(.tool, at: Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(AgentActivity.activityLabel(for: home, provider: .grok, wait: .tool) == "Reading")

        let shell = """
        {"params":{"timestamp":1800000001,"update":{"sessionUpdate":"tool_call","toolCallId":"call-2","rawInput":{"command":"swift test"},"_meta":{"x.ai/tool":{"name":"run_terminal_command","kind":"execute"}}}}}
        """
        try (shell + "\n").write(to: home, atomically: true, encoding: .utf8)
        #expect(AgentActivity.activityLabel(for: home, provider: .grok, wait: .tool) == "Testing…")
        let named = AgentActivity.lastToolCall(in: [Data(shell.utf8)])
        #expect(named == AgentActivity.ToolCall(name: "run_terminal_command", kind: .test))

        let done = """
        {"params":{"timestamp":1800000002,"update":{"sessionUpdate":"tool_call_update","toolCallId":"call-2","status":"completed"}}}
        """
        try (call + "\n" + done + "\n").write(to: home, atomically: true, encoding: .utf8)
        #expect(AgentActivity.verdict(for: home, provider: .grok) == .working(.model, at: Date(timeIntervalSince1970: 1_800_000_002)))
        #expect(AgentActivity.lastToolCall(in: [Data(done.utf8)]) == nil)
    }
}
