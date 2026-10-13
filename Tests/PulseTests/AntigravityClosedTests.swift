import Foundation
import Testing
@testable import Pulse

/// Antigravity's figures exist only while its language server runs, so with the
/// app closed the card has to fall back on the last reading — dated, and
/// dropped once its window has reset.
@Suite("Antigravity with the app closed")
struct AntigravityClosedTests {
    private static let account = AccountKey(.antigravity)

    private static func cache() -> UsageCache {
        UsageCache(file: FileManager.default.temporaryDirectory
            .appending(path: "pulse-antigravity-\(UUID().uuidString).json"))
    }

    private static func live(resetsIn seconds: TimeInterval, observed: Date = Date()) -> ProviderUsage {
        ProviderUsage(
            account: account,
            windows: [UsageWindow(
                id: "weekly", kind: .weekly, scope: "Gemini", usedFraction: 0.4,
                windowSeconds: 7 * 86_400, resetsAt: Date().addingTimeInterval(seconds), isExhausted: false
            )],
            observedAt: observed, state: .live, plan: "Pro", creditBalance: nil
        )
    }

    @Test("A closed app shows the last reading, marked stale and dated")
    func closedAppShowsLastReading() async {
        let cache = Self.cache()
        let observed = Date().addingTimeInterval(-600)
        _ = await cache.reconciled(Self.live(resetsIn: 86_400, observed: observed))

        let shown = await cache.reconciled(.unavailable(Self.account, reason: .antigravityNotRunning))
        #expect(shown.state == .stale)
        #expect(shown.windows.first?.usedFraction == 0.4)
        #expect(shown.plan == "Pro")
        #expect(shown.observedAt.map { abs($0.timeIntervalSince(observed)) < 1 } == true)
    }

    @Test("The last reading survives a relaunch of Pulse")
    func survivesRelaunch() async {
        let file = FileManager.default.temporaryDirectory.appending(path: "pulse-antigravity-\(UUID().uuidString).json")
        _ = await UsageCache(file: file).reconciled(Self.live(resetsIn: 86_400))

        let restored = await UsageCache(file: file).reconciled(.unavailable(Self.account, reason: .antigravityNotRunning))
        #expect(restored.state == .stale)
        #expect(restored.windows.count == 1)
    }

    @Test("A window that reset while the app was closed is not shown")
    func resetWindowIsDropped() async {
        let cache = Self.cache()
        _ = await cache.reconciled(Self.live(resetsIn: 3_600))
        let stored = await cache.lastReading(for: Self.account)
        #expect(stored != nil)

        let later = await cache.reconciled(Self.live(resetsIn: -60))
        #expect(later.state != .live)
    }
}
