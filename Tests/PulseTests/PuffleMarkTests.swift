import AppKit
import Foundation
import Testing
@testable import Pulse

@Suite("Puffles and the animation engine")
@MainActor
struct PuffleMarkTests {
    // MARK: - The catalogue

    @Test("Every colour ships, each variant on its own, with frames that load")
    func catalogue() throws {
        let all = PuffleCatalog.all
        #expect(all.count >= 36)
        #expect(Set(all.map(\.color)) == Set(PuffleCatalog.colors))
        #expect(Set(all.map(\.id)).count == all.count)
        for variant in all {
            let idle = try #require(variant.frames(.idle), "\(variant.id) has no idle")
            #expect(idle.count > 0 && idle.fps > 0)
            for size in [false, true] {
                let sheet = PuffleSheet.sheet(variant, large: size)
                let frame = try #require(sheet.frame(variant.still), "\(variant.id) still")
                #expect(frame.width == sheet.cell && frame.height == sheet.cell)
                let last = variant.clips.values.map { $0.start + $0.count - 1 }.max() ?? 0
                #expect(sheet.frame(last) != nil, "\(variant.id) atlas is short")
            }
        }
    }

    @Test("The orange puffle is two choices: the classic ball and the cat with ears and a tail")
    func orangeVariants() throws {
        let orange = PuffleCatalog.all.filter { $0.color == "orange" }
        let classic = try #require(orange.first { !$0.creature })
        let cat = try #require(orange.first { $0.source == "orange1007" })
        #expect(classic.id == "orange" && cat.id == "orange-cat")
        #expect(classic.id != cat.id)
        // Each from its own SWFs: the classic has the old care moods, the cat
        // its happy bob, and neither borrows the other's.
        #expect(classic.frames(.yawn) != nil && classic.frames(.bounce) == nil)
        #expect(cat.frames(.bounce) != nil && cat.frames(.yawn) == nil)
        // Grouped by colour, classic first.
        let group = try #require(PuffleCatalog.byColor.first { $0.color == "orange" })
        #expect(group.variants.first?.id == "orange")
        #expect(group.variants.count >= 3)
    }

    @Test("Each AI gets a puffle until one is chosen")
    func automaticPuffle() {
        #expect(PuffleCatalog.automatic(for: .claudeCode)?.id == "orange")
        #expect(PuffleCatalog.automatic(for: .antigravity)?.id == "blue")
        for provider in [Provider.codex, .grok, .cursor, .zai] {
            #expect(PuffleCatalog.automatic(for: provider) != nil)
        }
    }

    // MARK: - Moods

    @Test("Usage colours the idle time at 50, 75, 90 and 100 %")
    func usageThresholds() {
        #expect(MarkMood.resolve(pose: .awake, usedFraction: nil) == .idle)
        #expect(MarkMood.resolve(pose: .play, usedFraction: 0.49) == .idle)
        #expect(MarkMood.resolve(pose: .stretch, usedFraction: 0.5) == .concerned)
        #expect(MarkMood.resolve(pose: .tired, usedFraction: 0.75) == .tired)
        #expect(MarkMood.resolve(pose: .tired, usedFraction: 0.9) == .exhausted)
        #expect(MarkMood.resolve(pose: .spent, usedFraction: 1) == .spent)
        #expect(MarkMood.resolve(pose: .sleep, usedFraction: 1) == .spent)
        #expect(MarkMood.resolve(pose: .sleep, usedFraction: 0.2) == .asleep)
    }

    @Test("Work and the moments around it come before usage")
    func workFirst() {
        for pose in [MascotPose.run, .type, .thinking] {
            #expect(MarkMood.resolve(pose: pose, usedFraction: 0.95) == .working)
        }
        #expect(MarkMood.resolve(pose: .testing, usedFraction: 0.2) == .commandWait)
        #expect(MarkMood.resolve(pose: .celebrate, usedFraction: 0.8) == .celebrating)
        #expect(MarkMood.resolve(pose: .coffee, usedFraction: 0.8) == .resting)
        #expect(MarkMood.resolve(pose: .waiting, usedFraction: 0.1) == .needsYou)
        #expect(MarkMood.resolve(pose: .error, usedFraction: 0.1) == .error)
        #expect(MarkMood.resolve(pose: .awake, usedFraction: 0.3, justReset: true) == .revived)
        #expect(MarkMood.resolve(pose: .run, usedFraction: 0.3, justReset: true) == .working)
    }

    @Test("Only a spent limit holds still")
    func onlySpentIsStill() {
        #expect(MarkMood.allCases.filter(\.isStill) == [.spent])
    }

    @Test("Every mood has something to play, for every puffle and every mascot pose")
    func menusNeverEmpty() {
        for variant in PuffleCatalog.all {
            for mood in MarkMood.allCases {
                let menu = PuffleChoreography.menu(for: mood, variant: variant)
                #expect(!menu.isEmpty, "\(variant.id) \(mood)")
                #expect(menu.allSatisfy { variant.frames($0.value) != nil }, "\(variant.id) \(mood)")
            }
        }
        for mood in MarkMood.allCases {
            for pose in MascotPose.allCases {
                #expect(!MascotChoreography.menu(for: mood, pose: pose).isEmpty)
            }
        }
    }

    @Test("An idle mascot never shows a working pose")
    func idleNeverWorks() {
        for mood in [MarkMood.idle, .concerned, .tired, .exhausted, .resting, .asleep, .celebrating, .needsYou] {
            #expect(MascotChoreography.menu(for: mood, pose: .awake).allSatisfy { !$0.value.isWorking }, "\(mood)")
        }
        #expect(MascotChoreography.menu(for: .working, pose: .run).allSatisfy { $0.value.isWorking })
        #expect(MascotChoreography.menu(for: .working, pose: .type).first?.value == .type)
    }

    // MARK: - The choreographer

    private static func run(
        _ director: MarkChoreographer<MascotPose>, mood: MarkMood, menu: [MarkBeat<MascotPose>],
        from start: TimeInterval = 0, for seconds: TimeInterval, step: TimeInterval = 0.25
    ) -> [MascotPose] {
        var shown: [MascotPose] = []
        var time = start
        while time < start + seconds {
            let cue = director.cue(mood: mood, menu: menu, at: time)
            if shown.last != cue.value { shown.append(cue.value) }
            time += step
        }
        return shown
    }

    @Test("Idle rotates through weighted picks and never repeats one back to back")
    func noRepeats() {
        let director = MarkChoreographer<MascotPose>(seed: 7)
        let menu = MascotChoreography.menu(for: .idle, pose: .awake)
        var counts: [MascotPose: Int] = [:]
        var last: MascotPose?
        var lastStart = -1.0
        var time: TimeInterval = 0
        while time < 6 * 3600 {
            let cue = director.cue(mood: .idle, menu: menu, at: time)
            if cue.start != lastStart {
                #expect(cue.value != last, "repeated \(cue.value) at \(time)")
                counts[cue.value, default: 0] += 1
                last = cue.value
                lastStart = cue.start
            }
            time += 0.5
        }
        #expect(director.dealt > 1000)
        #expect(Set(counts.keys) == Set(menu.map(\.value)))
        // The heaviest pick comes up most.
        #expect(counts[.awake, default: 0] > counts[.coffee, default: 0])
    }

    @Test("The same seed deals the same programme; another seed another")
    func seeded() {
        let menu = MascotChoreography.menu(for: .idle, pose: .awake)
        let a = Self.run(MarkChoreographer(seed: 3), mood: .idle, menu: menu, for: 600)
        let b = Self.run(MarkChoreographer(seed: 3), mood: .idle, menu: menu, for: 600)
        let c = Self.run(MarkChoreographer(seed: 4), mood: .idle, menu: menu, for: 600)
        #expect(a == b)
        #expect(a != c)
        for pair in zip(a, a.dropFirst()) { #expect(pair.0 != pair.1) }
    }

    @Test("News cuts the beat short: a new mood opens on its lead beat at once")
    func moodChangeIsImmediate() {
        let director = MarkChoreographer<MascotPose>(seed: 9)
        _ = director.cue(mood: .idle, menu: MascotChoreography.menu(for: .idle, pose: .awake), at: 0)
        let cue = director.cue(mood: .celebrating, menu: MascotChoreography.menu(for: .celebrating, pose: .celebrate), at: 1)
        #expect(cue.value == .celebrate && cue.start == 1)
        // The status word changing within a working turn is news too.
        _ = director.cue(mood: .working, menu: MascotChoreography.menu(for: .working, pose: .type), at: 2)
        let moved = director.cue(mood: .working, menu: MascotChoreography.menu(for: .working, pose: .run), at: 3)
        #expect(moved.value == .run && moved.start == 3)
        #expect(moved.previous == .type)
    }

    @Test("A puffle's beat is held for whole loops, so a trick is never cut off")
    func wholeLoops() throws {
        let variant = try #require(PuffleCatalog.variant("orange"))
        let menu = PuffleChoreography.menu(for: .celebrating, variant: variant)
        var rng = SplitMix64(seed: 1)
        for beat in menu {
            let loop = try #require(beat.loop)
            for _ in 0..<20 {
                let length = MarkChoreographer<PuffleClip>.length(of: beat, using: &rng)
                let loops = length / loop
                #expect(abs(loops - loops.rounded()) < 1e-6 && loops >= 1)
            }
        }
    }

    // MARK: - Settings

    @Test("Each AI's mark is a logo, its mascot or a puffle, and the puffle is remembered")
    func markStyleSetting() throws {
        let claude = AccountKey(.claudeCode)
        let settings = AppSettings(enabledAccounts: [Provider.claudeCode.rawValue])
        settings.puffleMarks = [:]
        settings.setShowsBotMark(false, for: claude)
        #expect(settings.markStyle(for: claude) == .logo)

        settings.setMarkStyle(.puffle, for: claude)
        #expect(settings.markStyle(for: claude) == .puffle)
        #expect(settings.puffle(for: claude)?.id == "orange")
        #expect(!settings.showsBotMark(for: claude))
        #expect(settings.showsAnimatedMark(for: claude))

        let cat = try #require(PuffleCatalog.variant("orange-cat"))
        settings.setPuffle(cat, for: claude)
        #expect(settings.puffle(for: claude) == cat)
        // Choosing puffle again keeps the one picked.
        settings.setMarkStyle(.puffle, for: claude)
        #expect(settings.puffle(for: claude) == cat)

        settings.setMarkStyle(.mascot, for: claude)
        #expect(settings.markStyle(for: claude) == .mascot && settings.puffle(for: claude) == nil)
        settings.setMarkStyle(.logo, for: claude)
        #expect(settings.markStyle(for: claude) == .logo && !settings.showsAnimatedMark(for: claude))

        // A puffle a later version no longer ships reads as not a puffle.
        settings.puffleMarks = [claude.id: "puffle-that-never-was"]
        #expect(settings.markStyle(for: claude) == .logo)
        settings.puffleMarks = [:]
    }
}
