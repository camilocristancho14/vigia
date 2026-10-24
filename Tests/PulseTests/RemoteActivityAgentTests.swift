import Foundation
import Testing
@testable import Pulse

@Suite("Remote activity — named Grok Bot agents")
struct RemoteActivityAgentTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("One named agent working reads as '<name> working'")
    func oneAgent() {
        var ledger = RemoteActivityLedger()
        ledger.record(provider: .grokBot, source: "grok-bot", event: "UserPromptSubmit", tool: nil,
                      agent: "Dobby", at: t0)
        let state = ledger.state(for: .grokBot, now: t0.addingTimeInterval(5))
        #expect(state?.isWorking == true)
        #expect(state?.label == String.localized("Dobby working"))
    }

    @Test("Two named agents working at once are joined with 'and'")
    func twoAgents() {
        var ledger = RemoteActivityLedger()
        ledger.record(provider: .grokBot, source: "grok-bot", event: "UserPromptSubmit", tool: nil,
                      agent: "Dobby", at: t0)
        ledger.record(provider: .grokBot, source: "grok-bot", event: "UserPromptSubmit", tool: nil,
                      agent: "Neo", at: t0.addingTimeInterval(1))
        let label = ledger.state(for: .grokBot, now: t0.addingTimeInterval(5))?.label
        #expect(label == String.localized("Dobby and Neo working"))
    }

    @Test("Three or more named agents working collapse to a count")
    func threeOrMoreAgents() {
        var ledger = RemoteActivityLedger()
        for name in ["Dobby", "Neo", "Marcus"] {
            ledger.record(provider: .grokBot, source: "grok-bot", event: "UserPromptSubmit", tool: nil,
                          agent: name, at: t0)
        }
        let label = ledger.state(for: .grokBot, now: t0.addingTimeInterval(5))?.label
        #expect(label == String.localized("\(3) bots working"))
    }

    @Test("A finished agent shows briefly, then falls back to no state")
    func justFinished() {
        var ledger = RemoteActivityLedger()
        ledger.record(provider: .grokBot, source: "grok-bot", event: "UserPromptSubmit", tool: nil,
                      agent: "Dobby", at: t0)
        ledger.record(provider: .grokBot, source: "grok-bot", event: "Stop", tool: nil,
                      agent: "Dobby", at: t0.addingTimeInterval(10))

        let justAfter = ledger.state(for: .grokBot, now: t0.addingTimeInterval(11))
        #expect(justAfter?.isWorking == true)
        #expect(justAfter?.label == String.localized("Dobby finished"))

        #expect(ledger.state(for: .grokBot, now: t0.addingTimeInterval(20)) == nil)
    }

    @Test("One bot finishing doesn't interrupt another still working")
    func oneFinishesWhileAnotherWorks() {
        var ledger = RemoteActivityLedger()
        ledger.record(provider: .grokBot, source: "grok-bot", event: "UserPromptSubmit", tool: nil,
                      agent: "Dobby", at: t0)
        ledger.record(provider: .grokBot, source: "grok-bot", event: "UserPromptSubmit", tool: nil,
                      agent: "Neo", at: t0)
        ledger.record(provider: .grokBot, source: "grok-bot", event: "Stop", tool: nil,
                      agent: "Dobby", at: t0.addingTimeInterval(5))

        let label = ledger.state(for: .grokBot, now: t0.addingTimeInterval(6))?.label
        #expect(label == String.localized("Neo working"))
    }

    @Test("A hook that never names an agent keeps the old single-line behaviour")
    func noAgentFieldIsUnaffected() {
        var ledger = RemoteActivityLedger()
        ledger.record(provider: .claudeCode, source: "server", event: "UserPromptSubmit", tool: nil, at: t0)
        #expect(ledger.state(for: .claudeCode, now: t0.addingTimeInterval(5))?.label == "Thinking…")
    }

    @Test("Named agents under Grok Bot never leak into another provider's state")
    func scopedByProvider() {
        var ledger = RemoteActivityLedger()
        ledger.record(provider: .grokBot, source: "grok-bot", event: "UserPromptSubmit", tool: nil,
                      agent: "Dobby", at: t0)
        #expect(ledger.state(for: .claudeCode, now: t0.addingTimeInterval(1)) == nil)
    }

    @Test("A Grok Bot hook with no agent name reads as 'Grok Bot working'")
    func missingAgentDefaultsToGenericName() {
        var ledger = RemoteActivityLedger()
        ledger.record(provider: .grokBot, source: "grok-bot", event: "UserPromptSubmit", tool: nil, at: t0)
        let state = ledger.state(for: .grokBot, now: t0.addingTimeInterval(5))
        #expect(state?.isWorking == true)
        #expect(state?.label == String.localized("Grok Bot working"))
    }

    @Test("A Grok Bot hook with no agent name goes idle after its Stop")
    func missingAgentStopGoesIdle() {
        var ledger = RemoteActivityLedger()
        ledger.record(provider: .grokBot, source: "grok-bot", event: "UserPromptSubmit", tool: nil, at: t0)
        ledger.record(provider: .grokBot, source: "grok-bot", event: "Stop", tool: nil, at: t0.addingTimeInterval(10))

        let justAfter = ledger.state(for: .grokBot, now: t0.addingTimeInterval(11))
        #expect(justAfter?.label == String.localized("Grok Bot finished"))

        #expect(ledger.state(for: .grokBot, now: t0.addingTimeInterval(20)) == nil)
    }

    @Test("Working expires after 10 minutes without events, even mid test or build")
    func workingHasATenMinuteHardCap() {
        var ledger = RemoteActivityLedger()
        ledger.record(provider: .claudeCode, source: "server", event: "PreToolUse", tool: "bash",
                      kind: "test", at: t0)
        #expect(ledger.state(for: .claudeCode, now: t0.addingTimeInterval(599))?.isWorking == true)
        #expect(ledger.state(for: .claudeCode, now: t0.addingTimeInterval(601)) == nil)
    }
}
