import Foundation
import Testing
@testable import Pulse

@Suite("Mascot poses")
@MainActor
struct MascotPoseTests {
    @Test("A busy turn runs for commands and searches, and types for the rest")
    func workingPose() {
        #expect(MascotPose.working(label: "Running command") == .run)
        #expect(MascotPose.working(label: "Searching") == .run)
        #expect(MascotPose.working(label: "Delegating") == .run)
        #expect(MascotPose.working(label: "Editing") == .type)
        #expect(MascotPose.working(label: "Thinking…") == .type)
        #expect(MascotPose.working(label: nil) == .type)
        #expect(MascotPose.run.isWorking && MascotPose.type.isWorking)
        #expect(!MascotPose.coffee.isWorking && !MascotPose.sleep.isWorking)
    }

    @Test("Break after a turn, awake while recent, asleep after twenty quiet minutes")
    func waitingPose() async {
        let now = Date()
        let monitor = AgentActivityMonitor { _ in [:] }
        let store = UsageStore(settings: AppSettings(enabledAccounts: [Provider.claudeCode.rawValue]), activity: monitor)
        monitor.adoptDemo(running: [], finishedAt: [.claudeCode: now.addingTimeInterval(-120)])
        #expect(store.mascotPose(.claudeCode, now: now) == .coffee)
        #expect(store.mascotPose(.claudeCode, now: now.addingTimeInterval(700)) == .awake)
        #expect(store.mascotPose(.claudeCode, now: now.addingTimeInterval(1500)) == .sleep)

        monitor.adoptDemo(running: [.claudeCode], labels: [.claudeCode: "Running command"])
        #expect(store.mascotPose(.claudeCode, now: now) == .run)
    }

    @Test("Every pose has frames on the walking sprite's 51 × 36 grid")
    func spriteFrames() {
        for pose in [MascotPose.run, .type, .coffee, .awake, .sleep] {
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

        var napping = BotMarkProgramme.forMood(.idle, persona: .playful)
        napping.apply(pose: .sleep, activityLabel: nil)
        #expect(napping.states == ["drowsy", "sleeping"])

        var untouched = BotMarkProgramme.forMood(.idle, persona: .playful)
        let before = untouched.states
        untouched.apply(pose: .awake, activityLabel: nil)
        #expect(untouched.states == before)
    }
}
