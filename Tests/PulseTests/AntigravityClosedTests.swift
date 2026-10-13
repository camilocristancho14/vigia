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

    /// The shape of a real reading, banked from the language server and shown
    /// hours later with the app closed: two pools, each with a five-hour and a
    /// weekly window. The figures are the ones Antigravity reported (2% and 1%
    /// of Gemini gone, nothing of Claude and GPT); the times are moved to now.
    /// When the Gemini five-hour window turns over it alone goes — it has
    /// reset, so its old figure is about a window that no longer exists — and
    /// the three still running keep their banked figures and their date.
    @Test("A closed app keeps the running pools and drops only the one that reset")
    func closedAppDropsOnlyTheResetPool() async throws {
        let cache = Self.cache()
        let observed = Date().addingTimeInterval(-3.5 * 3_600)
        func window(_ id: String, _ kind: UsageWindow.Kind, _ scope: String, _ used: Double, resetsIn: TimeInterval) -> UsageWindow {
            UsageWindow(
                id: id, kind: kind, scope: scope, usedFraction: used,
                windowSeconds: kind == .fiveHour ? 5 * 3_600 : 7 * 86_400,
                resetsAt: Date().addingTimeInterval(resetsIn), isExhausted: false
            )
        }
        _ = await cache.reconciled(ProviderUsage(
            account: Self.account,
            windows: [
                window("gemini-5h", .fiveHour, "Gemini", 0.0241516, resetsIn: 0.5),
                window("gemini-weekly", .weekly, "Gemini", 0.0134236, resetsIn: 6 * 86_400),
                window("3p-5h", .fiveHour, "Claude and GPT", 0, resetsIn: 3_600),
                window("3p-weekly", .weekly, "Claude and GPT", 0, resetsIn: 6 * 86_400),
            ],
            observedAt: observed, state: .live, plan: "Pro", creditBalance: nil
        ))

        try await Task.sleep(for: .seconds(1))

        let shown = await cache.reconciled(.unavailable(Self.account, reason: .antigravityNotRunning))
        #expect(shown.state == .stale)
        #expect(shown.windows.map(\.id) == ["gemini-weekly", "3p-5h", "3p-weekly"])
        #expect(shown.windows.first?.percentText == "1%")
        #expect(shown.observedAt.map { abs($0.timeIntervalSince(observed)) < 1 } == true)
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
