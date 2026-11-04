// Club Penguin's puffles as an account's mark. Every frame is the game's own
// art: the sprites inside the original SWFs from media1.clubpenguin.com,
// recovered from the Wayback Machine and rasterised frame by frame by JPEXS
// ffdec — nothing redrawn or generated. `scripts/puffles/` rebuilds the
// atlases; `docs/animaciones.md` lists the sources and the clips. Puffles
// and Club Penguin are Disney's.
import AppKit
import SwiftUI

/// The animations a puffle can have. Which ones a variant has depends on
/// which of its SWFs survived in the archive; `puffles.json` says.
enum PuffleClip: String, CaseIterable, Sendable, Hashable {
    /// Facing out, blinking.
    case idle
    /// Turning its head to one side and back.
    case look
    /// The creature puffles' happy bob on the spot.
    case bounce
    /// Walking towards the viewer.
    case walk
    /// Walking past, in profile.
    case walkSide
    /// Eyes closing, nodding off.
    case doze
    /// Asleep under its Zs.
    case sleep
    /// Waking with a start.
    case wake
    case jump
    /// The jump with a spin, its best trick.
    case spin
    case nuzzle
    case roll
    /// Chattering away.
    case speak
    /// Standing on its head.
    case headstand
    case dig
    case eat
    case splash
    /// The Puffle Hotel's weightlifting.
    case lift
    /// The classic puffles' moods, from the game's own care screens: a long
    /// yawn, a thought bubble of food, and a queasy green tongue.
    case yawn
    case hungry
    case sick
}

/// Where one clip sits in a variant's atlas.
struct PuffleClipFrames: Decodable, Hashable, Sendable {
    let start: Int
    let count: Int
    let fps: Double

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
    let small: Int
    let large: Int
    let clips: [String: PuffleClipFrames]
    /// The frame it lies still on once the limit is spent.
    let still: Int

    var title: String {
        let language = LocalizationSource.locale.language.languageCode?.identifier ?? "en"
        return name[language] ?? name["en"] ?? id
    }

    func frames(_ clip: PuffleClip) -> PuffleClipFrames? { clips[clip.rawValue] }

    var available: [PuffleClip] { PuffleClip.allCases.filter { clips[$0.rawValue] != nil } }
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
        case .grok: "red"
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
/// Two atlases per variant: 44 px cells, which are the menu bar's 22 points
/// at 2×, and 80 px cells for the rail's rings and the settings preview, so
/// nothing on screen is drawn from frames smaller than it.
@MainActor
final class PuffleSheet {
    let variant: PuffleVariant
    let cell: Int
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
        cell = large ? variant.large : variant.small
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
        let rect = CGRect(x: (index % variant.columns) * cell, y: (index / variant.columns) * cell,
                          width: cell, height: cell)
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
/// A clip the variant does not have is left out; a mood left with nothing
/// falls back to the idle blink, which every puffle has.
enum PuffleChoreography {
    static func menu(for mood: MarkMood, variant: PuffleVariant) -> [MarkBeat<PuffleClip>] {
        let wanted: [(PuffleClip, Double, ClosedRange<TimeInterval>)] = switch mood {
        case .idle:
            [(.idle, 3, 4...8), (.look, 3, 3...6), (.bounce, 2, 3...5), (.jump, 1.5, 3...4),
             (.nuzzle, 1, 3...4), (.eat, 1, 3...5), (.dig, 1, 4...6), (.headstand, 1, 4...5),
             (.speak, 1, 2...3), (.doze, 0.6, 3...5), (.splash, 0.6, 3...4)]
        case .concerned:
            [(.look, 4, 3...6), (.hungry, 2, 3...4), (.idle, 3, 3...6), (.speak, 1.5, 2...3),
             (.walk, 1, 3...4), (.doze, 1, 3...4)]
        case .tired:
            [(.yawn, 4, 6...7), (.doze, 3, 5...8), (.idle, 2, 4...6), (.look, 1, 3...4)]
        case .exhausted:
            [(.doze, 4, 5...8), (.yawn, 3, 6...7), (.sick, 2, 2...4), (.sleep, 2, 6...10)]
        case .spent:
            [(.sleep, 1, 60...60)]
        case .working:
            [(.walk, 3, 4...7), (.walkSide, 3, 4...7), (.roll, 2, 3...5), (.dig, 2, 4...6),
             (.jump, 1.5, 3...4), (.lift, 2, 4...6), (.bounce, 1, 3...4), (.spin, 0.5, 2...3)]
        case .commandWait:
            [(.dig, 3, 5...8), (.look, 2, 3...5), (.idle, 1, 3...5), (.walk, 1, 3...5)]
        case .needsYou:
            [(.speak, 4, 3...5), (.bounce, 2, 2...4), (.jump, 2, 2...3), (.look, 1, 2...3)]
        case .waking:
            [(.wake, 1, 2...3), (.bounce, 1, 2...3)]
        case .celebrating:
            [(.spin, 4, 3...5), (.headstand, 2, 3...5), (.jump, 2, 2...4), (.bounce, 2, 2...4),
             (.roll, 1, 3...4), (.walk, 0.5, 2...3)]
        case .resting:
            [(.eat, 4, 4...7), (.nuzzle, 3, 3...5), (.idle, 2, 3...6), (.splash, 1, 3...5),
             (.look, 1, 3...4)]
        case .asleep:
            [(.sleep, 6, 20...40), (.doze, 1, 4...6)]
        case .error:
            [(.sick, 4, 3...5), (.look, 3, 3...5), (.speak, 2, 2...3), (.doze, 1, 3...4)]
        case .revived:
            [(.wake, 2, 2...3), (.spin, 2, 3...4), (.bounce, 1, 2...3), (.jump, 1, 2...3)]
        }
        let menu: [MarkBeat<PuffleClip>] = wanted.compactMap { entry in
            variant.frames(entry.0).map { MarkBeat(entry.0, weight: entry.1, entry.2, loop: $0.loop / mood.tempo) }
        }
        if !menu.isEmpty { return menu }
        let idle = variant.frames(.idle)
        return [MarkBeat(.idle, weight: 1, 4...8, loop: idle.map { $0.loop / mood.tempo })]
    }
}

/// A puffle, animated by `MarkChoreographer` from the agent's pose and the
/// limit, cross-fading from one clip to the next.
///
/// **Light on the battery.** A puffle is redrawn only as often as its clip
/// has frames — twelve and a half a second, half that asleep, and half again
/// in Low Power Mode — from frames cut once and kept. A spent puffle and
/// Reduce Motion are a single still image with no timeline at all.
struct PuffleMarkView: View {
    let variant: PuffleVariant
    let pose: MascotPose
    var usedFraction: Double?
    var justReset = false
    let size: CGFloat
    /// Whatever tells this mark from its neighbours, so they never move in step.
    var seed = ""

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
        .scaleEffect(large ? 1.0 : 1.22)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func interval(for mood: MarkMood) -> TimeInterval {
        let base: TimeInterval = mood == .asleep || mood == .exhausted || mood == .spent ? 1 / 6.25 : 1 / 12.5
        return ProcessInfo.processInfo.isLowPowerModeEnabled ? base * 2 : base
    }

    @ViewBuilder
    private func still(_ sheet: PuffleSheet, mood: MarkMood) -> some View {
        let frame = (mood.isStill || mood == .asleep || mood == .spent) ? sheet.frame(variant.still) : sheet.frame(.idle, at: 0)
        image(frame)
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
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }
}

extension MarkChoreographer where Value == PuffleClip {
    func cueing(mood: MarkMood, variant: PuffleVariant, seed: String, at time: TimeInterval) -> MarkCue<PuffleClip> {
        seedIfNeeded(variant.id + "|" + seed)
        return cue(mood: mood, menu: PuffleChoreography.menu(for: mood, variant: variant), at: time)
    }
}

/// Puts an AI mascot through `MascotChoreography`: the pose it is shown in
/// changes every few seconds within its mood, cross-fading, and a spent limit
/// holds it still.
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
        if mood.isStill || reduceMotion {
            content(pose, mood.isStill)
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
                           size: 64, seed: "preview")
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
