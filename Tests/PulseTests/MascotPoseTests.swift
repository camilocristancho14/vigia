import Foundation
import Testing
@testable import Pulse

@Suite("Mascot poses")
@MainActor
struct MascotPoseTests {
    @Test("At the laptop for commands and edits, on the move for looking things up")
    func workingPose() {
        #expect(MascotPose.working(label: "Running command") == .type)
        #expect(MascotPose.working(label: "Editing") == .type)
        #expect(MascotPose.working(label: "Thinking…") == .type)
        #expect(MascotPose.working(label: nil) == .type)
        #expect(MascotPose.working(label: "Searching") == .run)
        #expect(MascotPose.working(label: "Reading") == .run)
        #expect(MascotPose.working(label: "Delegating") == .run)
        #expect(MascotPose.run.isWorking && MascotPose.type.isWorking)
        #expect(!MascotPose.coffee.isWorking && !MascotPose.sleep.isWorking)
        #expect(!MascotPose.tired.isWorking && !MascotPose.spent.isWorking)
    }

    @Test("Where sessions are visible: work, then a break, then the limit, then awake or asleep")
    func waitingPose() async {
        let now = Date()
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.claudeCode.rawValue]), activity: monitor)

        monitor.adoptDemo(running: [], finishedAt: [.claudeCode: now.addingTimeInterval(-120)])
        #expect(store.mascotPose(.claudeCode, now: now) == .coffee)
        // The break outranks the limit.
        #expect(store.mascotPose(.claudeCode, usedFraction: 1, now: now) == .coffee)
        // Break over: a nearly or fully spent limit shows, otherwise awake.
        let later = now.addingTimeInterval(400)
        #expect(store.mascotPose(.claudeCode, usedFraction: 0.5, now: later) == .awake)
        #expect(store.mascotPose(.claudeCode, usedFraction: 0.75, now: later) == .tired)
        #expect(store.mascotPose(.claudeCode, usedFraction: 0.999, now: later) == .tired)
        #expect(store.mascotPose(.claudeCode, usedFraction: 1, now: later) == .spent)
        // Long quiet: asleep, unless a limit is the news.
        let muchLater = now.addingTimeInterval(1500)
        #expect(store.mascotPose(.claudeCode, usedFraction: 0.1, now: muchLater) == .sleep)
        #expect(store.mascotPose(.claudeCode, usedFraction: 0.9, now: muchLater) == .tired)

        // Work outranks everything.
        monitor.adoptDemo(running: [.claudeCode], labels: [.claudeCode: "Running command"])
        #expect(store.mascotPose(.claudeCode, usedFraction: 1, now: now) == .type)
    }

    @Test("An agent that cannot be watched follows its limit, then the clock")
    func unwatchedPose() {
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.grokBot.rawValue]), activity: monitor)
        #expect(!Provider.grokBot.supportsLocalActivity)
        let noon = Self.date(hour: 10, minute: 20)
        #expect(store.mascotPose(.grokBot, usedFraction: 1, playful: true, now: noon) == .spent)
        #expect(store.mascotPose(.grokBot, usedFraction: 0.8, playful: true, now: noon) == .tired)
        #expect(store.mascotPose(.grokBot, usedFraction: 0.3, playful: true, now: noon) == MascotPose.ofTheDay(at: noon, playful: true))
        // Even a session somewhere else cannot make it "work".
        monitor.adoptDemo(running: [.grok], labels: [.grok: "Searching"])
        #expect(!store.isRunning(.grokBot))
    }

    @Test("Through the day: asleep at night, coffee early, then varied scenes")
    func dayPose() {
        #expect(MascotPose.ofTheDay(at: Self.date(hour: 2, minute: 0), playful: true) == .sleep)
        #expect(MascotPose.ofTheDay(at: Self.date(hour: 23, minute: 30), playful: false) == .sleep)
        #expect(MascotPose.ofTheDay(at: Self.date(hour: 7, minute: 30), playful: true) == .coffee)
        let scenes = Set((0..<48).map { MascotPose.ofTheDay(at: Self.date(hour: 9 + $0 / 4, minute: ($0 % 4) * 15), playful: true) })
        #expect(scenes.isSuperset(of: [.awake, .type, .run, .coffee]))
        let plain = Set((0..<48).map { MascotPose.ofTheDay(at: Self.date(hour: 9 + $0 / 4, minute: ($0 % 4) * 15), playful: false) })
        #expect(plain.isSubset(of: [.awake, .coffee]))
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour, minute: minute)) ?? Date()
    }

    @Test("Every pose has frames on the walking sprite's 51 × 36 grid")
    func spriteFrames() {
        for pose in [MascotPose.run, .type, .coffee, .awake, .sleep, .tired, .spent] {
            for colour in [true, false] {
                let frame = ClawdFrames.frame(for: pose, at: 0.3, colour: colour)
                #expect(frame != nil)
                #expect(frame?.size == NSSize(width: 51, height: 36))
            }
        }
    }

    @Test("The bot plays the scenes that look like what the agent is doing")
    func botScenes() {
        var writing = BotMarkProgramme.forMood(.working, persona: .calm)
        writing.apply(pose: .type, activityLabel: "Writing")
        #expect(writing.states == ["writing", "working"])

        var worn = BotMarkProgramme.forMood(.idle, persona: .calm)
        worn.apply(pose: .tired, activityLabel: nil)
        #expect(worn.states == ["drowsy", "bored", "sad"])

        var drained = BotMarkProgramme.forMood(.spent, persona: .calm)
        drained.apply(pose: .spent, activityLabel: nil)
        #expect(drained.states == ["powering-down", "sad"])

        var napping = BotMarkProgramme.forMood(.idle, persona: .playful)
        napping.apply(pose: .sleep, activityLabel: nil)
        #expect(napping.states == ["drowsy", "sleeping"])

        var untouched = BotMarkProgramme.forMood(.idle, persona: .playful)
        let before = untouched.states
        untouched.apply(pose: .awake, activityLabel: nil)
        #expect(untouched.states == before)
    }
}
