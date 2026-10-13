import Foundation
import Testing
@testable import Pulse

@Suite("Mascot poses")
@MainActor
struct MascotPoseTests {
    @Test("Thinking on the model's move, at the laptop for commands and edits, on the move for looking things up")
    func workingPose() {
        #expect(MascotPose.working(label: "Running command") == .type)
        #expect(MascotPose.working(label: "Editing") == .type)
        #expect(MascotPose.working(label: "Using tool") == .type)
        #expect(MascotPose.working(label: "Thinking…") == .thinking)
        #expect(MascotPose.working(label: nil) == .thinking)
        #expect(MascotPose.working(label: "Searching") == .run)
        #expect(MascotPose.working(label: "Reading") == .run)
        #expect(MascotPose.working(label: "Delegating") == .run)
        #expect(MascotPose.run.isWorking && MascotPose.type.isWorking && MascotPose.thinking.isWorking)
        let idle = MascotPose.allCases.filter { ![.run, .type, .thinking].contains($0) }
        #expect(idle.allSatisfy { !$0.isWorking })
    }

    @Test("Where sessions are visible: up, work, celebration, a break, then the limit, then idle or asleep")
    func waitingPose() {
        let now = Self.date(hour: 14, minute: 0)
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.claudeCode.rawValue]), activity: monitor)

        monitor.adoptDemo(running: [], finishedAt: [.claudeCode: now.addingTimeInterval(-5)],
                          lastWrites: [.claudeCode: now.addingTimeInterval(-5)])
        #expect(store.mascotPose(.claudeCode, now: now) == .celebrate)
        let soon = now.addingTimeInterval(115)
        #expect(store.mascotPose(.claudeCode, now: soon) == .coffee)
        // The break outranks the limit.
        #expect(store.mascotPose(.claudeCode, usedFraction: 1, now: soon) == .coffee)
        // Break over: a nearly or fully spent limit shows, otherwise idle.
        let later = now.addingTimeInterval(400)
        let idle = store.mascotPose(.claudeCode, usedFraction: 0.5, now: later)
        #expect(MascotPose.daytime.contains(idle) && !idle.isWorking)
        #expect(store.mascotPose(.claudeCode, usedFraction: 0.75, now: later) == .tired)
        #expect(store.mascotPose(.claudeCode, usedFraction: 0.999, now: later) == .tired)
        #expect(store.mascotPose(.claudeCode, usedFraction: 1, now: later) == .spent)
        // Long quiet: asleep, unless a limit is the news.
        let muchLater = now.addingTimeInterval(1500)
        #expect(store.mascotPose(.claudeCode, usedFraction: 0.1, now: muchLater) == .sleep)
        #expect(store.mascotPose(.claudeCode, usedFraction: 0.9, now: muchLater) == .tired)

        // Work outranks everything, after a moment getting up.
        monitor.adoptDemo(running: [.claudeCode], labels: [.claudeCode: "Running command"],
                          startedAt: [.claudeCode: now.addingTimeInterval(-1)])
        #expect(store.mascotPose(.claudeCode, usedFraction: 1, now: now) == .waking)
        #expect(store.mascotPose(.claudeCode, usedFraction: 1, now: now.addingTimeInterval(10)) == .type)
    }

    @Test("Idle for over twenty minutes is asleep, at any hour, whatever its slot")
    func inactiveSleeps() {
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.claudeCode.rawValue]), activity: monitor)
        for hour in [7, 10, 13, 16, 20] {
            let now = Self.date(hour: hour, minute: 10)
            monitor.adoptDemo(running: [], lastWrites: [.claudeCode: now.addingTimeInterval(-21 * 60)])
            for slot in 0..<6 {
                #expect(store.mascotPose(.claudeCode, slot: slot, now: now) == .sleep)
            }
            // Never written at all: asleep too, not working.
            monitor.adoptDemo(running: [], lastWrites: [:])
            #expect(store.mascotPose(.claudeCode, now: now) == .sleep)
        }
    }

    @Test("Another provider's activity does not keep this one awake")
    func noCrossProviderFallback() {
        let now = Self.date(hour: 15, minute: 0)
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.claudeCode.rawValue, Provider.codex.rawValue]),
                               activity: monitor)
        monitor.adoptDemo(running: [], lastWrites: [.codex: now.addingTimeInterval(-30)])
        #expect(monitor.lastWrite != nil)
        #expect(store.mascotPose(.claudeCode, now: now) == .sleep)
        #expect(store.mascotPose(.codex, now: now) != .sleep)
    }

    @Test("A turn waiting for a person, and a failed turn, have their own poses")
    func waitingAndFailed() {
        let now = Self.date(hour: 11, minute: 0)
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.claudeCode.rawValue]), activity: monitor)
        monitor.adoptDemo(running: [], waiting: [.claudeCode])
        #expect(store.mascotPose(.claudeCode, usedFraction: 1, now: now) == .waiting)
        monitor.adoptDemo(running: [], failedAt: [.claudeCode: now.addingTimeInterval(-60)])
        #expect(store.mascotPose(.claudeCode, now: now) == .error)
        #expect(store.mascotPose(.claudeCode, now: now.addingTimeInterval(AgentActivity.failureWindow)) == .sleep)
        // Spent is the limit, error is the agent: not the same pose.
        #expect(MascotPose.error != MascotPose.spent)
    }

    @Test("An agent that cannot be watched follows its limit, then the clock")
    func unwatchedPose() {
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.grokBot.rawValue]), activity: monitor)
        #expect(!Provider.grokBot.supportsLocalActivity)
        let noon = Self.date(hour: 10, minute: 20)
        #expect(store.mascotPose(.grokBot, usedFraction: 1, now: noon) == .spent)
        #expect(store.mascotPose(.grokBot, usedFraction: 0.8, now: noon) == .tired)
        #expect(store.mascotPose(.grokBot, usedFraction: 0.3, slot: 2, now: noon) == MascotPose.ofTheDay(slot: 2, at: noon))
        // Even a session somewhere else cannot make it "work".
        monitor.adoptDemo(running: [.grok], labels: [.grok: "Searching"])
        #expect(!store.isRunning(.grokBot))
    }

    @Test("Through the day: asleep at night, never at work while idle, more than coffee in the morning")
    func dayPose() {
        #expect(MascotPose.ofTheDay(at: Self.date(hour: 2, minute: 0)) == .sleep)
        #expect(MascotPose.ofTheDay(at: Self.date(hour: 23, minute: 30)) == .sleep)
        for hour in 0..<24 {
            for minute in stride(from: 0, to: 60, by: 5) {
                for slot in 0..<6 {
                    #expect(!MascotPose.ofTheDay(slot: slot, at: Self.date(hour: hour, minute: minute)).isWorking)
                }
            }
        }
        let morning = Set((0..<36).map { MascotPose.ofTheDay(at: Self.date(hour: 6 + $0 / 12, minute: ($0 % 12) * 5)) })
        #expect(morning.count >= 4)
        #expect(morning.isSuperset(of: [.coffee, .awake, .waking, .stretch]))
        let day = Set((0..<48).map { MascotPose.ofTheDay(at: Self.date(hour: 9 + $0 / 4, minute: ($0 % 4) * 15)) })
        #expect(day == Set(MascotPose.daytime))
    }

    @Test("Marks on one surface are dealt different poses", arguments: [1, 2, 3, 4, 5])
    func jointPoses(count: Int) {
        for (hour, minute) in [(7, 5), (10, 0), (14, 35), (18, 55)] {
            let now = Self.date(hour: hour, minute: minute)
            let poses = (0..<count).map { MascotPose.ofTheDay(slot: $0, at: now) }
            let distinct = Set(poses).count
            let available = (6..<9).contains(hour) ? MascotPose.morning.count : MascotPose.daytime.count
            // All different while there are poses to go round, then each
            // repeated as few times as possible.
            #expect(distinct == min(count, available))
            let most = Dictionary(grouping: poses, by: { $0 }).values.map(\.count).max() ?? 0
            #expect(most == Int((Double(count) / Double(available)).rounded(.up)))
        }
    }

    @Test("Two accounts of the same provider do not mirror each other")
    func sameProviderTwice() {
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.grokBot.rawValue]), activity: monitor)
        for minute in stride(from: 0, to: 60, by: 5) {
            let now = Self.date(hour: 12, minute: minute)
            #expect(store.mascotPose(.grokBot, usedFraction: 0.2, slot: 0, now: now)
                    != store.mascotPose(.grokBot, usedFraction: 0.2, slot: 1, now: now))
        }
    }

    @Test("Animation phases come from a hash that is the same every launch")
    func stableHash() {
        #expect(StableHash.fnv1a("") == 0xcbf2_9ce4_8422_2325)
        #expect(StableHash.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(Provider.codex.mascotPhase == StableHash.phase(Provider.codex.rawValue))
        #expect(Provider.codex.mascotPhase != Provider.antigravity.mascotPhase)
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour, minute: minute)) ?? Date()
    }

    @Test("The bot plays the scenes that look like what the agent is doing")
    func botScenes() {
        var writing = BotMarkProgramme.forMood(.working, persona: .calm)
        writing.apply(pose: .type, activityLabel: "Writing")
        #expect(writing.states == ["writing", "working"])

        var thinking = BotMarkProgramme.forMood(.working, persona: .calm)
        thinking.apply(pose: .thinking, activityLabel: "Thinking…")
        #expect(thinking.states == ["thinking", "working"])

        var worn = BotMarkProgramme.forMood(.idle, persona: .calm)
        worn.apply(pose: .tired, activityLabel: nil)
        #expect(worn.states == ["drowsy", "bored", "sad"])

        var drained = BotMarkProgramme.forMood(.spent, persona: .calm)
        drained.apply(pose: .spent, activityLabel: nil)
        #expect(drained.states == ["powering-down", "sad"])

        var napping = BotMarkProgramme.forMood(.idle, persona: .playful)
        napping.apply(pose: .sleep, activityLabel: nil)
        #expect(napping.states == ["drowsy", "sleeping"])

        var asking = BotMarkProgramme.forMood(.idle, persona: .calm)
        asking.apply(pose: .waiting, activityLabel: nil)
        #expect(asking.states.first == "notifying")

        var starting = BotMarkProgramme.forMood(.working, persona: .calm)
        starting.apply(pose: .waking, activityLabel: nil)
        #expect(starting.states == ["spawning", "waking"])

        var failed = BotMarkProgramme.forMood(.idle, persona: .calm)
        failed.apply(pose: .error, activityLabel: nil)
        #expect(failed.poseShape == "teardrop" && failed.crossedEyes)
        #expect(failed.configuration(for: failed.states[0]).crossedEyes)

        var done = BotMarkProgramme.forMood(.idle, persona: .calm)
        done.apply(pose: .celebrate, activityLabel: nil)
        #expect(done.states.first == "celebrate" && done.poseShape == "star")
        let library = BotMarkLibrary.shared
        #expect(library.shapes["star"] == nil)
        #expect(library.shape("star").ring.count == library.shape("blob").ring.count)
        #expect(library.shape("star").ring != library.shape("blob").ring)

        var untouched = BotMarkProgramme.forMood(.idle, persona: .playful)
        let before = untouched.states
        untouched.apply(pose: .awake, activityLabel: nil)
        #expect(untouched.states == before)
    }
}
