import Foundation
import Testing
@testable import Pulse

/// A limit the agent says it hit shows at once, without waiting for a poll.
@Suite("Live limits")
@MainActor
struct LiveLimitTests {
    private static var bogota: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        return calendar
    }

    /// 2026-10-13 16:20 in Bogota.
    private static var now: Date { date(2026, 10, 13, 16, 20) }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        bogota.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    // MARK: - The words

    @Test("Claude Code's session message gives the next time the clock reads that hour, in its own zone")
    func sessionMessage() throws {
        let hit = try #require(LimitHit.parseClaude(
            "You've hit your session limit · resets 5pm (America/Bogota)", at: Self.now, calendar: Self.bogota))
        #expect(hit.window == .session)
        #expect(hit.resetsAt == Self.date(2026, 10, 13, 17, 0))

        // A time already gone today is tomorrow's.
        let early = try #require(LimitHit.parseClaude(
            "You've hit your session limit · resets 3:30pm (America/Bogota)", at: Self.now, calendar: Self.bogota))
        #expect(early.resetsAt == Self.date(2026, 10, 14, 15, 30))
    }

    @Test("The zone in the message wins over the machine's")
    func zoneInMessage() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let hit = try #require(LimitHit.parseClaude(
            "You've hit your session limit · resets 5pm (America/Bogota)", at: Self.now, calendar: utc))
        #expect(hit.resetsAt == Self.date(2026, 10, 13, 17, 0))
    }

    @Test("Weekly messages carry a date; other limits are neither window")
    func weeklyAndOthers() throws {
        let weekly = try #require(LimitHit.parseClaude(
            "You've hit your weekly limit · resets Oct 17, 3pm (America/Bogota)", at: Self.now, calendar: Self.bogota))
        #expect(weekly.window == .weekly)
        #expect(weekly.resetsAt == Self.date(2026, 10, 17, 15, 0))

        let opus = try #require(LimitHit.parseClaude(
            "You've hit your Opus limit · resets 6:20pm (America/Bogota)", at: Self.now, calendar: Self.bogota))
        #expect(opus.window == .other)

        let old = try #require(LimitHit.parseClaude("Claude AI usage limit reached|1791946800", at: Self.now))
        #expect(old.resetsAt == Date(timeIntervalSince1970: 1_791_946_800) && old.window == .session)

        #expect(LimitHit.parseClaude("Prompt is too long", at: Self.now) == nil)
        #expect(LimitHit.parseClaude("Login expired · Please run /login", at: Self.now) == nil)
    }

    @Test("Codex's rate_limits say which window ran out and when it lifts")
    func codexLimits() throws {
        let reset = Self.now.addingTimeInterval(3600).timeIntervalSince1970
        let spent: [String: Any] = [
            "primary": ["used_percent": 100.0, "window_minutes": 300, "resets_at": reset],
            "secondary": ["used_percent": 41.0, "window_minutes": 10_080, "resets_at": reset + 86_400]
        ]
        let hit = try #require(LimitHit.parseCodex(spent, at: Self.now))
        #expect(hit.window == .session && hit.resetsAt == Date(timeIntervalSince1970: reset))

        let weekly: [String: Any] = ["primary": ["used_percent": 100, "window_minutes": 10_080, "resets_at": reset]]
        #expect(LimitHit.parseCodex(weekly, at: Self.now)?.window == .weekly)

        let fine: [String: Any] = ["primary": ["used_percent": 62.0, "window_minutes": 300, "resets_at": reset],
                                   "rate_limit_reached_type": NSNull()]
        #expect(LimitHit.parseCodex(fine, at: Self.now) == nil)
    }

    // MARK: - The transcripts

    private static func claudeRecord(_ text: String, error: Bool, at date: Date, stop: String? = "stop_sequence") -> [String: Any] {
        var record: [String: Any] = [
            "type": "assistant", "timestamp": stamp(date),
            "message": ["stop_reason": stop as Any, "content": [["type": "text", "text": text]]]
        ]
        if error {
            record["isApiErrorMessage"] = true
            record["error"] = "rate_limit"
            record["apiError"] = "usage_limit_reached"
        }
        return record
    }

    @Test("A Claude Code transcript ending on the limit message is a limit, and not a failed turn")
    func claudeTranscript() throws {
        let home = try EditorTestSupport.temporary("claude-limit")
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appending(path: ".claude/projects/demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appending(path: "session.jsonl")
        let at = Self.now.addingTimeInterval(-600)

        try EditorTestSupport.jsonLines([
            Self.claudeRecord("Done.", error: false, at: at.addingTimeInterval(-60)),
            ["type": "user", "timestamp": Self.stamp(at.addingTimeInterval(-30)), "message": ["content": "go on"]],
            Self.claudeRecord("You've hit your session limit · resets 5pm (America/Bogota)", error: true, at: at)
        ], to: file)
        try FileManager.default.setAttributes([.modificationDate: at], ofItemAtPath: file.path)

        #expect(AgentActivity.verdict(for: file, provider: .claudeCode) == .finished)
        let hit = try #require(AgentActivity.limit(for: file, provider: .claudeCode, now: Self.now, calendar: Self.bogota))
        #expect(hit.window == .session && hit.resetsAt == Self.date(2026, 10, 13, 17, 0))

        // The monitor sees it even though the file is ten minutes old, and
        // the turn is neither working nor failed.
        let state = try #require(AgentActivity.states(for: [.claudeCode], now: Self.now, home: home)[.claudeCode])
        #expect(state.limit?.window == .session)
        #expect(!state.isWorking && state.failedAt == nil)

        // The agent answering afterwards means the limit has lifted.
        try EditorTestSupport.jsonLines([
            Self.claudeRecord("You've hit your session limit · resets 5pm (America/Bogota)", error: true, at: at),
            Self.claudeRecord("Back again.", error: false, at: at.addingTimeInterval(120))
        ], to: file)
        #expect(AgentActivity.limit(for: file, provider: .claudeCode, now: Self.now, calendar: Self.bogota) == nil)
    }

    @Test("The record's own quotaLimits give the reset exactly, whatever the sentence says")
    func structuredLimits() throws {
        let home = try EditorTestSupport.temporary("claude-quota")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: "session.jsonl")
        var record = Self.claudeRecord("You've hit your session limit · resets 5pm (America/Bogota)", error: true, at: Self.now)
        record["quotaLimits"] = ["status": "rejected", "resetsAt": 1_791_928_800, "rateLimitType": "five_hour",
                                 "overageStatus": "rejected", "isUsingOverage": false]
        try EditorTestSupport.jsonLines([record], to: file)
        let hit = try #require(AgentActivity.limit(for: file, provider: .claudeCode, now: Self.now))
        #expect(hit.window == .session && hit.resetsAt == Date(timeIntervalSince1970: 1_791_928_800))

        // The weekly window, from the same block under apiErrorParams.
        record["quotaLimits"] = nil
        record["apiErrorParams"] = ["rate_limit_info": ["status": "rejected", "resetsAt": 1_792_292_400, "rateLimitType": "seven_day"]]
        try EditorTestSupport.jsonLines([record], to: file)
        #expect(AgentActivity.limit(for: file, provider: .claudeCode, now: Self.now)?.window == .weekly)

        // A warning that blocks nothing is not a hit.
        #expect(LimitHit.parseClaudeInfo(["status": "allowed_warning", "resetsAt": 1_792_292_400, "rateLimitType": "seven_day"], at: Self.now) == nil)
    }

    @Test("Other API errors are failures, not limits")
    func otherErrors() throws {
        let home = try EditorTestSupport.temporary("claude-auth")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: "session.jsonl")
        var record = Self.claudeRecord("Login expired · Please run /login", error: true, at: Self.now)
        record["error"] = "authentication_failed"
        record["apiError"] = nil
        try EditorTestSupport.jsonLines([record], to: file)
        #expect(AgentActivity.limit(for: file, provider: .claudeCode, now: Self.now) == nil)
        #expect(AgentActivity.verdict(for: file, provider: .claudeCode) == .failed(at: Self.now.addingTimeInterval(0)))
    }

    @Test("Codex: the newest token_count decides")
    func codexTranscript() throws {
        let home = try EditorTestSupport.temporary("codex-limit")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: "rollout.jsonl")
        let reset = Self.now.addingTimeInterval(1800).timeIntervalSince1970
        func count(_ used: Double, _ at: Date) -> [String: Any] {
            ["timestamp": Self.stamp(at), "payload": ["type": "token_count", "rate_limits": [
                "primary": ["used_percent": used, "window_minutes": 300, "resets_at": reset]]]]
        }
        try EditorTestSupport.jsonLines([count(40, Self.now.addingTimeInterval(-900)), count(100, Self.now.addingTimeInterval(-60))], to: file)
        #expect(AgentActivity.limit(for: file, provider: .codex, now: Self.now)?.window == .session)
        try EditorTestSupport.jsonLines([count(100, Self.now.addingTimeInterval(-900)), count(12, Self.now.addingTimeInterval(-60))], to: file)
        #expect(AgentActivity.limit(for: file, provider: .codex, now: Self.now) == nil)
    }

    // MARK: - On the panel

    private static func reading(used: Double, observed: Date, resetsIn: TimeInterval = 4.5 * 3600) -> ProviderUsage {
        ProviderUsage(
            account: AccountKey(.claudeCode),
            windows: [
                UsageWindow(id: "5h", kind: .fiveHour, scope: nil, usedFraction: used, windowSeconds: 5 * 3600,
                            resetsAt: now.addingTimeInterval(resetsIn)),
                UsageWindow(id: "7d", kind: .weekly, scope: nil, usedFraction: 0.18, windowSeconds: 7 * 86_400,
                            resetsAt: now.addingTimeInterval(4 * 86_400))
            ],
            observedAt: observed, state: .live, plan: nil, creditBalance: nil)
    }

    @Test("A limit the agent hit turns the stale reading red, with the reset the message gave")
    func overlay() {
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.claudeCode.rawValue]), activity: monitor)
        let account = AccountKey(.claudeCode)
        let polled = Self.now.addingTimeInterval(-1800)
        store.adopt(Self.reading(used: 0.14, observed: polled))
        #expect(store.usage(for: account, now: Self.now).windows[0].usedFraction == 0.14)

        let reset = Self.date(2026, 10, 13, 17, 0)
        monitor.adoptDemo(running: [], limits: [.claudeCode: LimitHit(at: Self.now.addingTimeInterval(-600), resetsAt: reset, window: .session)])
        let shown = store.usage(for: account, now: Self.now)
        #expect(UsageTint.isSpent(shown.windows[0]) && shown.windows[0].resetsAt == reset)
        // The other window, and the age of the reading, are left alone.
        #expect(shown.windows[1].usedFraction == 0.18)
        #expect(shown.observedAt == polled)
        #expect(store.mascotPose(.claudeCode, usedFraction: shown.windows[0].usedFraction, now: Self.now) == .spent)

        // Once the reset has passed it no longer binds.
        #expect(store.usage(for: account, now: reset.addingTimeInterval(1)).windows[0].usedFraction == 0.14)
    }

    @Test("A session that ran into its limit is spent at once, not on a coffee break")
    func hitTurnShowsSpent() {
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.claudeCode.rawValue]), activity: monitor)
        let account = AccountKey(.claudeCode)
        store.adopt(Self.reading(used: 0.9, observed: Self.now.addingTimeInterval(-1800)))
        let reset = Self.now.addingTimeInterval(3 * 3600)
        // The turn ended on the limit a minute ago: before, that read as a
        // finished turn and Clawd had his coffee for five minutes.
        monitor.adoptDemo(running: [], finishedAt: [.claudeCode: Self.now.addingTimeInterval(-60)],
                          limits: [.claudeCode: LimitHit(at: Self.now.addingTimeInterval(-60), resetsAt: reset, window: .session)])
        let shown = store.usage(for: account, now: Self.now)
        #expect(UsageTint.isSpent(shown.windows[0]))
        #expect(store.mascotPose(.claudeCode, usedFraction: 1, now: Self.now) == .spent)
        // Once it resets, the break is back to what it was.
        monitor.adoptDemo(running: [], finishedAt: [.claudeCode: reset.addingTimeInterval(60)],
                          limits: [.claudeCode: LimitHit(at: Self.now.addingTimeInterval(-60), resetsAt: reset, window: .session)])
        #expect(store.mascotPose(.claudeCode, usedFraction: 1, now: reset.addingTimeInterval(120)) == .celebrate
                || store.mascotPose(.claudeCode, usedFraction: 1, now: reset.addingTimeInterval(120)) == .coffee)
    }

    @Test("A reading newer than the hit is the provider's own word and stands")
    func newerReadingStands() {
        let hit = LimitHit(at: Self.now.addingTimeInterval(-600), resetsAt: Self.date(2026, 10, 13, 17, 0), window: .session)
        let window = Self.reading(used: 0.3, observed: Self.now).windows[0]
        #expect(window.applying(hit, readAt: Self.now, now: Self.now).usedFraction == 0.3)
        #expect(window.applying(hit, readAt: Self.now.addingTimeInterval(-900), now: Self.now).usedFraction == 1)
        // A limit for another window leaves this one alone.
        let weekly = LimitHit(at: hit.at, resetsAt: hit.resetsAt, window: .weekly)
        #expect(window.applying(weekly, readAt: nil, now: Self.now).usedFraction == 0.3)
    }

    @Test("A new limit asks for fresh figures at once, but only once in half a minute")
    func asksAtOnce() async throws {
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.claudeCode.rawValue]), activity: monitor)
        _ = store
        var heard: [Provider] = []
        monitor.onNewLimit = { provider, _ in heard.append(provider) }
        let hit = LimitHit(at: Self.now, resetsAt: Self.now.addingTimeInterval(3600), window: .session)
        monitor.publish(limits: [.claudeCode: hit])
        monitor.publish(limits: [.claudeCode: hit])
        #expect(heard == [.claudeCode])
        monitor.publish(limits: [:])
        monitor.publish(limits: [.claudeCode: hit])
        #expect(heard == [.claudeCode, .claudeCode])
    }

    // MARK: - The cadence

    @Test("The menu bar keeps the figures live with the panel hidden; an agent writing tightens it to a minute")
    func cadence() {
        let now = Self.now
        var signals = AdaptiveRefresh.Signals(lastAgentActivity: now.addingTimeInterval(-30), isPanelVisible: false)
        // Nothing shows them at all: half an hour, as before.
        #expect(AdaptiveRefresh.interval(for: signals, now: now) == AdaptiveRefresh.ceiling)
        // The menu bar is showing: not half an hour.
        signals.showsInMenuBar = true
        #expect(AdaptiveRefresh.interval(for: signals, now: now) == AdaptiveRefresh.live)
        signals.lastAgentActivity = now.addingTimeInterval(-200)
        #expect(AdaptiveRefresh.interval(for: signals, now: now) == AdaptiveRefresh.floor)
        signals.lastAgentActivity = now.addingTimeInterval(-3 * 3600)
        #expect(AdaptiveRefresh.interval(for: signals, now: now) <= 900)
    }
}
