import Foundation
import Testing
@testable import Pulse

@Suite("Grok's unified card")
struct GrokUnifiedUsageTests {
    private func window(_ id: String, _ kind: UsageWindow.Kind, _ used: Double) -> UsageWindow {
        UsageWindow(id: id, kind: kind, scope: nil, usedFraction: used, windowSeconds: 7 * 86_400, resetsAt: nil)
    }

    private func live(_ provider: Provider, _ windows: [UsageWindow], plan: String? = nil) -> ProviderUsage {
        ProviderUsage(account: AccountKey(provider), windows: windows, observedAt: Date(),
                      state: .live, plan: plan, creditBalance: nil)
    }

    @Test("Grok Build's weekly pool wins over Grok Bot's copy of it, and Cursor's pools are not shown")
    func merges() {
        let merged = GrokUnifiedUsage.merge(
            grok: live(.grok, [window("weekly", .weekly, 1)], plan: "SuperGrok"),
            grokBot: live(.grokBot, [window("grokBot", .weekly, 1)], plan: "Grok Bot Plan")
        )
        #expect(merged.account == AccountKey(.grok))
        #expect(merged.windows.map(\.id) == ["weekly"])
        #expect(merged.plan == "SuperGrok")
    }

    @Test("Grok Bot stands in for the weekly pool when Grok Build has no reading")
    func fallsBack() {
        let merged = GrokUnifiedUsage.merge(
            grok: .unavailable(.grok, reason: .grokSignInRequired),
            grokBot: live(.grokBot, [window("grokBot", .weekly, 0.4)])
        )
        #expect(merged.state == .live)
        #expect(merged.windows.map(\.id) == ["grokBot"])
    }

    @Test("Nothing readable anywhere reports Grok Build's own reason")
    func nothing() {
        let merged = GrokUnifiedUsage.merge(
            grok: .unavailable(.grok, reason: .grokSignInRequired),
            grokBot: .unavailable(.grokBot, reason: .cursorSignInRequired)
        )
        #expect(merged.state == .unavailable(.grokSignInRequired))
    }

    @Test("Grok Bot and Cursor are never offered on their own")
    func hidden() {
        #expect(!Provider.builtIn.contains(.grokBot))
        #expect(!Provider.builtIn.contains(.cursor))
        #expect(Provider.grok.displayName == "Grok")
    }
}
