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
}
