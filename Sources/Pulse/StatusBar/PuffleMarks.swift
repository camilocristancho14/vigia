// Club Penguin's puffles as an account's mark. Every frame is the game's own
// art: the sprites inside the original SWFs from media1.clubpenguin.com,
// recovered from the Wayback Machine and rasterised frame by frame by JPEXS
// ffdec — nothing redrawn or generated. `scripts/puffles/` rebuilds the
// atlases; `docs/animaciones.md` lists the sources and the clips. Puffles
// and Club Penguin are Disney's.
import AppKit
import SwiftUI

/// One of a puffle's animations, by the name `puffles.json` gives it.
///
/// Which ones a variant has depends on which of its SWFs survived in the
/// archive: the classic colours carry their toys, baths and care-screen
/// moods, the creatures mostly their walks and tricks. The ones every
/// puffle may have are named here; the rest are only ever reached through
/// their `PuffleKind`.
struct PuffleClip: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { rawValue = value }
    var description: String { rawValue }

    /// Facing out, blinking (the ghost: floating).
    static let idle: PuffleClip = "idle"
    /// Turning its head to one side and back.
    static let look: PuffleClip = "look"
    /// The creature puffles' happy bob on the spot.
    static let bounce: PuffleClip = "bounce"
    static let walk: PuffleClip = "walk"
    static let walkSide: PuffleClip = "walkSide"
    /// Eyes closing, nodding off.
    static let doze: PuffleClip = "doze"
    /// Asleep under its Zs.
    static let sleep: PuffleClip = "sleep"
    /// Waking with a start.
    static let wake: PuffleClip = "wake"
    static let jump: PuffleClip = "jump"
    /// The jump with a spin, its best trick.
    static let spin: PuffleClip = "spin"
    static let nuzzle: PuffleClip = "nuzzle"
    static let roll: PuffleClip = "roll"
    static let speak: PuffleClip = "speak"
    static let headstand: PuffleClip = "headstand"
    static let dig: PuffleClip = "dig"
    static let eat: PuffleClip = "eat"
    static let splash: PuffleClip = "splash"
    static let lift: PuffleClip = "lift"
    /// The classic puffles' moods, from the game's own care screens: a long
    /// yawn, a thought bubble of food, and a queasy green tongue.
    static let yawn: PuffleClip = "yawn"
    static let hungry: PuffleClip = "hungry"
    static let sick: PuffleClip = "sick"
}

/// What an animation means, which decides the moods that play it. Every
/// clip in `puffles.json` carries one; `docs/animaciones.md` has the table.
enum PuffleKind: String, CaseIterable, Sendable, Decodable {
    /// At rest: breathing, blinking.
    case rest
    /// Looking about.
    case look
    /// Pondering, a thought crossing its face.
    case think
    case walk
    /// Busy at something: rolling, digging, weights, the easel, the camera,
    /// the unicycle, the skipping rope.
    case work
    /// Bursting with energy: the black puffle's fire, the white one's ice.
    case power
    /// A toy: gum, a beach ball, a skateboard, a hoop, a balloon…
    case play
    /// Its tricks: jumps, the spin, the headstand, the creatures' bob.
    case trick
    /// The disco ball.
    case dance
    /// Content: a nuzzle, being petted.
    case happy
    /// Tickled, laughing.
    case laugh
    /// The big moments: full care, delight, a trampoline, the cannon.
    case cheer
    case eat
    case bath
    /// Being brushed.
    case groom
    case speak
    /// A start: poked, the jack-in-the-box.
    case surprise
    /// Disappointed, upset.
    case sad
    case sick
    case yawn
    case hungry
    case doze
    /// Asleep: the Zs, the pillow, the dream.
    case sleep
    case wake
}

/// Where one clip sits in a variant's atlas, and what it is.
struct PuffleClipFrames: Decodable, Hashable, Sendable {
    let start: Int
    let count: Int
    let fps: Double
    let kind: PuffleKind

    var loop: TimeInterval { Double(count) / fps }
}

/// One puffle a mark can be: a colour, and for the colours that have more
/// than one, which of its looks — the classic ball, or one of the creature
/// puffles with ears, tails or horns.
struct PuffleVariant: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    /// The colour family, `orange`, `blue`, … in the order the picker groups them.
    let color: String
    /// The id the game used in its file names: `orange`, `orange1007`, …
    let source: String
    let name: [String: String]
    /// A creature puffle rather than the classic ball.
    let creature: Bool
    let columns: Int
    /// Cell heights, in pixels: 44 is the menu bar's 22 points at 2×.
    let small: Int
    let large: Int
    /// Cell widths: as wide as the variant's clips need, cut to the puffle.
    let smallWidth: Int
    let largeWidth: Int
    let clips: [String: PuffleClipFrames]
    /// The frame it lies still on once the limit is spent.
    let still: Int

    var title: String {
        let language = LocalizationSource.locale.language.languageCode?.identifier ?? "en"
        return name[language] ?? name["en"] ?? id
    }

    func frames(_ clip: PuffleClip) -> PuffleClipFrames? { clips[clip.rawValue] }

    /// Every clip it has, in a stable order.
    var available: [PuffleClip] { clips.keys.sorted().map(PuffleClip.init(rawValue:)) }

    /// Its clips of one kind, in a stable order.
    func animations(of kind: PuffleKind) -> [PuffleClip] {
        clips.filter { $0.value.kind == kind }.keys.sorted().map(PuffleClip.init(rawValue:))
    }

    /// Width over height of its cells: the puffle cut to its own size.
    var aspect: CGFloat { CGFloat(smallWidth) / CGFloat(max(small, 1)) }
}

/// The puffles in the app, read once from `puffles.json`.
enum PuffleCatalog {
    private struct Manifest: Decodable {
        let variants: [PuffleVariant]
    }

    /// The colour families, in the order the picker shows them.
    static let colors = ["blue", "pink", "black", "green", "purple", "red", "yellow", "white",
                         "orange", "brown", "gold", "rainbow"]

    static let all: [PuffleVariant] = {
        guard let url = Bundle.pulseResources.url(forResource: "puffles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.variants
    }()

    static func variant(_ id: String?) -> PuffleVariant? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// One colour's variants, for the picker.
    struct ColorGroup: Identifiable, Sendable {
        let color: String
        let variants: [PuffleVariant]
        var id: String { color }
    }

    /// Each colour's variants, classic first.
    static var byColor: [ColorGroup] {
        colors.compactMap { color in
            let variants = all.filter { $0.color == color }
            return variants.isEmpty ? nil : ColorGroup(color: color, variants: variants)
        }
    }

    /// The puffle an AI gets until somebody picks one: a colour that goes
    /// with its brand.
    static func automatic(for provider: Provider) -> PuffleVariant? {
        let wanted: String = switch provider {
        case .claudeCode: "orange"
        case .codex: "white"
        case .antigravity, .gemini: "blue"
        case .grok: "black"
        case .cursor: "purple"
        default:
            colors[Int(StableHash.fnv1a(provider.rawValue) % UInt64(colors.count))]
        }
        return all.first { $0.color == wanted && !$0.creature } ?? all.first
    }

    static func colorTitle(_ color: String) -> String {
        switch color {
        case "blue": .localized("Blue")
        case "pink": .localized("Pink")
        case "black": .localized("Black")
        case "green": .localized("Green")
        case "purple": .localized("Purple")
        case "red": .localized("Red")
        case "yellow": .localized("Yellow")
        case "white": .localized("White")
        case "orange": .localized("Orange")
        case "brown": .localized("Brown")
        case "gold": .localized("Gold")
        case "rainbow": .localized("Rainbow")
        default: color
        }
    }
}

/// A variant's frames at one size, cut from its atlas on first use and kept.
///
/// Two atlases per variant: cells 44 px tall, which are the menu bar's 22
/// points at 2×, and 80 px tall for the rail's rings and the settings
/// preview, so nothing on screen is drawn from frames smaller than it. Each
/// is as wide as the variant needs: the transparent margin is cut away.
@MainActor
final class PuffleSheet {
    let variant: PuffleVariant
    let cellWidth: Int
    let cellHeight: Int
    private let atlas: CGImage?
    private var frames: [Int: CGImage] = [:]

    private static var sheets: [String: PuffleSheet] = [:]

    static func sheet(_ variant: PuffleVariant, large: Bool) -> PuffleSheet {
        let key = variant.id + (large ? "-large" : "-small")
        if let sheet = sheets[key] { return sheet }
        let sheet = PuffleSheet(variant: variant, large: large)
        sheets[key] = sheet
        return sheet
    }

    private init(variant: PuffleVariant, large: Bool) {
        self.variant = variant
        cellHeight = large ? variant.large : variant.small
        cellWidth = large ? variant.largeWidth : variant.smallWidth
        let name = "puffle-\(variant.id)-\(large ? "large" : "small")"
        if let url = Bundle.pulseResources.url(forResource: name, withExtension: "png"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            atlas = CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            atlas = nil
        }
    }

    /// The atlas's `index`th frame.
    func frame(_ index: Int) -> CGImage? {
        if let frame = frames[index] { return frame }
        guard let atlas, index >= 0 else { return nil }
        let rect = CGRect(x: (index % variant.columns) * cellWidth, y: (index / variant.columns) * cellHeight,
                          width: cellWidth, height: cellHeight)
        let frame = atlas.cropping(to: rect)
        frames[index] = frame
        return frame
    }

    /// The frame `elapsed` seconds into a clip, looping.
    func frame(_ clip: PuffleClip, at elapsed: TimeInterval, tempo: Double = 1) -> CGImage? {
        guard let frames = variant.frames(clip), frames.count > 0 else { return frame(variant.still) }
        let step = Int((max(elapsed, 0) * frames.fps * tempo).rounded(.down))
        return frame(frames.start + step % frames.count)
    }
}

/// What a puffle rotates through in each mood, from what its SWFs gave it.
///
/// **Each animation where it means something.** A mood asks for kinds —
/// work while a turn is in flight, yawns and dozing as the limit runs low,
/// the trampoline and the disco ball when a turn has finished, sleep when it
/// is spent — and everything a puffle has of that kind is on its menu. The
/// kinds no state claims (toys, baths, tricks) fill the idle rotation, which
/// the choreographer deals without repeating itself.
///
/// A kind the variant does not have is left out; a mood left with nothing
/// falls back on its own fallbacks and, last, the idle blink every puffle has.
enum PuffleChoreography {
    typealias Wish = (kind: PuffleKind, weight: Double, seconds: ClosedRange<TimeInterval>)

    static func wishes(for mood: MarkMood) -> [[Wish]] {
        switch mood {
        case .idle:
            [[(.rest, 3, 4...8), (.look, 2, 3...6), (.play, 4, 4...10), (.trick, 2, 3...5),
              (.happy, 1.5, 3...5), (.laugh, 1, 2...4), (.bath, 1, 4...8), (.groom, 1, 3...6),
              (.eat, 1, 3...6), (.think, 1, 2...4), (.dance, 1, 4...8), (.speak, 0.5, 2...3),
              (.doze, 0.3, 3...5)]]
        case .concerned:
            [[(.look, 3, 3...6), (.think, 3, 3...5), (.hungry, 2, 3...4), (.rest, 2, 3...6),
              (.speak, 1, 2...3), (.walk, 1, 3...4), (.doze, 1, 3...4), (.sad, 0.5, 2...4)]]
        case .tired:
            [[(.yawn, 4, 6...7), (.doze, 3, 5...8), (.hungry, 2, 3...4), (.sad, 1.5, 3...5),
              (.sick, 1, 2...4), (.rest, 1, 4...6)]]
        case .exhausted:
            [[(.doze, 4, 5...8), (.yawn, 3, 6...7), (.sick, 2, 2...4), (.sad, 2, 3...5),
              (.sleep, 2, 6...10)]]
        case .spent:
            // Asleep — under its Zs, on its pillow — first; failing that,
            // nodding off or yawning; failing that, breathing slowly. Never
            // a still picture.
            [[(.sleep, 1, 20...40)], [(.doze, 1, 8...12), (.yawn, 1, 6...7)], [(.rest, 1, 8...12)]]
        case .working:
            [[(.walk, 3, 4...7), (.work, 4, 4...8), (.power, 1, 3...5), (.trick, 0.5, 2...3)]]
        case .commandWait:
            [[(.work, 2, 5...8), (.look, 2, 3...5), (.think, 2, 3...5), (.rest, 1, 3...5),
              (.walk, 1, 3...5)]]
        case .needsYou:
            [[(.speak, 4, 3...5), (.think, 2, 3...4), (.trick, 2, 2...4), (.look, 1, 2...3)]]
        case .waking:
            [[(.wake, 2, 2...3), (.surprise, 1, 2...4), (.trick, 0.5, 2...3)]]
        case .celebrating:
            [[(.cheer, 4, 3...6), (.trick, 3, 3...5), (.dance, 2, 4...6), (.laugh, 1.5, 2...4),
              (.happy, 1, 2...3)]]
        case .resting:
            [[(.eat, 4, 4...7), (.bath, 3, 5...8), (.groom, 2, 4...6), (.happy, 2, 3...5),
              (.laugh, 1, 2...4), (.rest, 1, 3...6), (.play, 1, 4...6)]]
        case .asleep:
            [[(.sleep, 6, 20...40), (.doze, 1, 4...6)]]
        case .error:
            [[(.sad, 4, 3...5), (.sick, 3, 3...5), (.look, 1, 3...5), (.think, 1, 2...3)],
             [(.doze, 1, 3...4), (.look, 1, 3...4)]]
        case .revived:
            [[(.wake, 2, 2...3), (.cheer, 2, 3...5), (.trick, 2, 3...4), (.surprise, 1, 2...3)]]
        }
    }

    static func menu(for mood: MarkMood, variant: PuffleVariant) -> [MarkBeat<PuffleClip>] {
        for tier in wishes(for: mood) {
            let menu: [MarkBeat<PuffleClip>] = tier.flatMap { wish -> [MarkBeat<PuffleClip>] in
                let clips = variant.animations(of: wish.kind)
                // A kind with many clips does not crowd out the others.
                let share = wish.weight / Double(max(clips.count, 1)).squareRoot()
                return clips.compactMap { clip in
                    variant.frames(clip).map { MarkBeat(clip, weight: share, wish.seconds, loop: $0.loop / mood.tempo) }
                }
            }
            if !menu.isEmpty { return menu }
        }
        let idle = variant.frames(.idle)
        return [MarkBeat(.idle, weight: 1, 4...8, loop: idle.map { $0.loop / mood.tempo })]
    }
}

/// A puffle, animated by `MarkChoreographer` from the agent's pose and the
/// limit, cross-fading from one clip to the next.
///
/// **Light on the battery.** A puffle is redrawn only as often as its clip
/// has frames — twelve and a half a second, half that asleep, and half again
/// in Low Power Mode — from frames cut once and kept. Reduce Motion is a
/// single still image with no timeline at all.
///
/// **As tall as it is given.** `size` is the height: the cells are cut to
/// the puffle, so in the menu bar it stands the bar's full 22 points and is
/// as wide as it needs (`width`). Where it must fit a circle — the rail's
/// rings, the settings preview — `square` fits it inside `size` × `size`.
///
/// **Never still when spent**: it sleeps, faded, so it reads as out.
struct PuffleMarkView: View {
    let variant: PuffleVariant
    let pose: MascotPose
    var usedFraction: Double?
    var justReset = false
    let size: CGFloat
    /// Whatever tells this mark from its neighbours, so they never move in step.
    var seed = ""
    /// Fitted inside a `size` square rather than `size` tall.
    var square = false

    /// How wide it is drawn for a height of `size`.
    static func width(of variant: PuffleVariant, height: CGFloat) -> CGFloat {
        (height * variant.aspect).rounded(.up)
    }

    private var width: CGFloat { square ? size : Self.width(of: variant, height: size) }

    @State private var director = MarkChoreographer<PuffleClip>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long two clips are faded across.
    static let fade: TimeInterval = 0.3

    /// Anything bigger than the menu bar's 22 points draws from the large atlas.
    private var large: Bool { size > 22.5 }

    var body: some View {
        let mood = MarkMood.resolve(pose: pose, usedFraction: usedFraction, justReset: justReset)
        let sheet = PuffleSheet.sheet(variant, large: large)
        Group {
            if reduceMotion {
                still(sheet, mood: mood)
            } else {
                TimelineView(.animation(minimumInterval: Self.interval(for: mood))) { context in
                    animated(sheet, mood: mood, at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        // Spent: asleep and a little faded, so it reads as out.
        .opacity(mood.isSpent ? 0.6 : 1)
        .frame(width: width, height: size)
        .accessibilityHidden(true)
    }

    static func interval(for mood: MarkMood) -> TimeInterval {
        let base: TimeInterval = mood == .asleep || mood == .exhausted || mood == .spent ? 1 / 6.25 : 1 / 12.5
        return ProcessInfo.processInfo.isLowPowerModeEnabled ? base * 2 : base
    }

    @ViewBuilder
    private func still(_ sheet: PuffleSheet, mood: MarkMood) -> some View {
        image(mood.isSpent ? sheet.frame(variant.still) : sheet.frame(.idle, at: 0))
    }

    @ViewBuilder
    private func animated(_ sheet: PuffleSheet, mood: MarkMood, at time: TimeInterval) -> some View {
        let cue = director.cueing(mood: mood, variant: variant, seed: seed, at: time)
        let into = time - cue.start
        let fading = cue.previous != nil && into < Self.fade
        ZStack {
            if fading, let previous = cue.previous {
                // The old clip held on the frame it was cut at.
                image(sheet.frame(previous, at: cue.start - cue.previousStart, tempo: mood.tempo))
                    .opacity(1 - into / Self.fade)
            }
            image(sheet.frame(cue.value, at: into, tempo: mood.tempo))
                .opacity(fading ? into / Self.fade : 1)
        }
    }

    private func image(_ frame: CGImage?) -> some View {
        Group {
            if let frame {
                Image(decorative: frame, scale: 2)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: size)
    }
}

extension MarkChoreographer where Value == PuffleClip {
    func cueing(mood: MarkMood, variant: PuffleVariant, seed: String, at time: TimeInterval) -> MarkCue<PuffleClip> {
        seedIfNeeded(variant.id + "|" + seed)
        return cue(mood: mood, menu: PuffleChoreography.menu(for: mood, variant: variant), at: time)
    }
}

/// Puts an AI mascot through `MascotChoreography`: the pose it is shown in
/// changes every few seconds within its mood, cross-fading. A spent limit
/// moves too — its spent pose, and asleep — only Reduce Motion holds still.
struct ChoreographedMascot<Content: View>: View {
    let pose: MascotPose
    var usedFraction: Double?
    var justReset = false
    var seed = ""
    @ViewBuilder let content: (_ pose: MascotPose, _ still: Bool) -> Content

    @State private var director = MarkChoreographer<MascotPose>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let mood = MarkMood.resolve(pose: pose, usedFraction: usedFraction, justReset: justReset)
        if reduceMotion {
            content(pose, true)
        } else {
            // A beat lasts seconds, so once a second is often enough to ask.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let shown = shownPose(mood: mood, at: context.date.timeIntervalSinceReferenceDate)
                ZStack {
                    content(shown, false)
                        .id(shown)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.35), value: shown)
            }
        }
    }

    private func shownPose(mood: MarkMood, at time: TimeInterval) -> MascotPose {
        director.seedIfNeeded("mascot|" + seed)
        return director.cue(mood: mood, menu: MascotChoreography.menu(for: mood, pose: pose), at: time).value
    }
}

/// What draws an account's mark, chosen per AI in its settings.
enum MarkStyle: String, CaseIterable, Identifiable, Sendable {
    /// The AI company's logo, animated by pose.
    case logo
    /// The AI's own mascot: Clawd, Float Bot, Cloud Ghost, the bot…
    case mascot
    /// A Club Penguin puffle of any colour or variant.
    case puffle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logo: .localized("Logo")
        case .mascot: .localized("Mascot")
        case .puffle: .localized("Puffle")
        }
    }
}

/// The chosen puffle, large and at menu bar size, in a mood of the reader's
/// choosing, so a variant can be judged before it is in the bar.
struct PufflePreview: View {
    let variant: PuffleVariant

    enum Sample: String, CaseIterable, Identifiable {
        case idle, working, celebrating, tired, spent
        var id: String { rawValue }

        var title: String {
            switch self {
            case .idle: .localized("Idle")
            case .working: .localized("Working")
            case .celebrating: .localized("Celebrating")
            case .tired: .localized("Tired")
            case .spent: .localized("Spent")
            }
        }

        var pose: MascotPose {
            switch self {
            case .idle: .awake
            case .working: .run
            case .celebrating: .celebrate
            case .tired: .tired
            case .spent: .spent
            }
        }

        var used: Double {
            switch self {
            case .tired: 0.8
            case .spent: 1
            default: 0.2
            }
        }
    }

    @State private var sample = Sample.idle

    var body: some View {
        HStack(spacing: 16) {
            PuffleMarkView(variant: variant, pose: sample.pose, usedFraction: sample.used,
                           size: 64, seed: "preview", square: true)
                .id(variant.id + sample.rawValue)
            PuffleMarkView(variant: variant, pose: sample.pose, usedFraction: sample.used,
                           size: 22, seed: "preview-bar")
                .id(variant.id + sample.rawValue + "bar")
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Spacer(minLength: 8)
            Picker("", selection: $sample) {
                ForEach(Sample.allCases) { sample in
                    Text(verbatim: sample.title).tag(sample)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
