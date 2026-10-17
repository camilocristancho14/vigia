import Foundation
import Testing
@testable import Pulse

/// What turns an account red in the menu, the menu bar icon and the settings
/// sidebar — and, as importantly, what does not.
@Suite("Needs attention")
struct NeedsAttentionTests {
    private let claude = AccountKey(.claudeCode)
    private let codex = AccountKey(.codex)
    private let cursor = AccountKey(.cursor)

    private func live(_ account: AccountKey) -> ProviderUsage {
        ProviderUsage(account: account, windows: [], observedAt: Date(), state: .live, plan: nil, creditBalance: nil)
    }

    @Test("Something to sign in to, paste or open is red")
    func fixable() {
        for reason: ProviderUsage.Unavailability in [
            .apiKeyMissing, .apiKeyRefused, .signedOut, .claudeLoginExpired,
            .sessionExpired, .codexNotInstalled, .notConnected, .extensionFailed
        ] {
            #expect(ProviderUsage.unavailable(claude, reason: reason).needsAttention, "\(reason)")
        }
    }

    @Test("What clears on its own, or is an answer about the plan, is not")
    func notFixable() {
        for reason: ProviderUsage.Unavailability in [
            .loading, .awaitingResponse, .unreachable, .rateLimited, .serverError,
            .unreadableReply, .noLimitsReported, .noPlan, .zaiNoCodingPlan
        ] {
            #expect(!ProviderUsage.unavailable(claude, reason: reason).needsAttention, "\(reason)")
        }
    }

    @Test("A reading, live or stale, is never red")
    func readings() {
        #expect(!live(claude).needsAttention)
        let stale = ProviderUsage(account: claude, windows: [], observedAt: Date(), state: .stale, plan: nil, creditBalance: nil)
        #expect(!stale.needsAttention)
    }

    @Test("Only the accounts asked about, in the order given")
    func filtering() {
        let readings: [AccountKey: ProviderUsage] = [
            claude: .unavailable(claude, reason: .claudeLoginExpired),
            codex: live(codex),
            cursor: .unavailable(cursor, reason: .cursorSignInRequired),
        ]
        let usage = { (account: AccountKey) in readings[account] ?? .unavailable(account, reason: .loading) }
        #expect(UsageStore.needingAttention([cursor, codex, claude], usage: usage) == [cursor, claude])
        // A switched-off account is simply not in the list it is given.
        #expect(UsageStore.needingAttention([codex], usage: usage).isEmpty)
        #expect(UsageStore.needingAttention([], usage: usage).isEmpty)
    }
}
