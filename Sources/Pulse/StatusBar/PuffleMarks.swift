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

extension PuffleClip {
    /// The clips with the puffle asleep or nodding off in them — `wake`
    /// opens asleep under its Zs, and a yawn is the start of a doze. Only a
    /// tired or spent limit plays them: a puffle at work, or waiting with
    /// plenty of its limit left, never looks asleep.
    static let sleepy: Set<PuffleClip> = [.doze, .sleep, .wake, .yawn]

    var isSleepy: Bool { Self.sleepy.contains(self) }
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

/// How big the puffle is in one clip of the large atlas, measured by
/// `scripts/puffles/measure_bodies.py` from the atlas itself. All in large
/// atlas pixels; boxes are `[x0, y0, x1, y1]` from the cell's top left.
struct PuffleBodyMetrics: Decodable, Hashable, Sendable {
    /// The puffle's height: the median over the clip's frames.
    let body: Double
    /// The idle puffle's body over this one's.
    let bodyScale: Double
    /// Everything in every frame: Zs, bubbles and props too.
    let box: [Double]
    /// The puffle alone, over every frame: what must never be cut.
    let bodyBox: [Double]
}

/// Where one clip sits in a variant's atlas, what it is, and how big the puffle is in it.
struct PuffleClipFrames: Decodable, Hashable, Sendable {
    let start: Int
    let count: Int
    let fps: Double
    let kind: PuffleKind
    let body: Double?
    let bodyScale: Double?
    let box: [Double]?
    let bodyBox: [Double]?

    private enum CodingKeys: String, CodingKey {
        case start, count, fps, kind, body, bodyScale, box, bodyBox
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Int.self, forKey: .start)
        count = try container.decode(Int.self, forKey: .count)
        fps = try container.decode(Double.self, forKey: .fps)
        kind = try container.decodeIfPresent(PuffleKind.self, forKey: .kind) ?? .rest
        body = try container.decodeIfPresent(Double.self, forKey: .body)
        bodyScale = try container.decodeIfPresent(Double.self, forKey: .bodyScale)
        box = try container.decodeIfPresent([Double].self, forKey: .box)
        bodyBox = try container.decodeIfPresent([Double].self, forKey: .bodyBox)
    }

    init(start: Int, count: Int, fps: Double, kind: PuffleKind = .rest, metrics: PuffleBodyMetrics? = nil) {
        self.start = start
        self.count = count
        self.fps = fps
        self.kind = kind
        body = metrics?.body
        bodyScale = metrics?.bodyScale
        box = metrics?.box
        bodyBox = metrics?.bodyBox
    }

    var loop: TimeInterval { Double(count) / fps }

    var metrics: PuffleBodyMetrics? {
        guard let body, let bodyScale, let box, box.count == 4, let bodyBox, bodyBox.count == 4 else { return nil }
        return PuffleBodyMetrics(body: body, bodyScale: bodyScale, box: box, bodyBox: bodyBox)
    }
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
    /// How big the puffle is in that frame.
    var stillMetrics: PuffleBodyMetrics?

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
/// Two atlases per variant: 44 px cells for the menu's small rows, and 80 px
/// cells that every animated mark — the menu bar's included — is drawn down
/// from, so a clip whose puffle is small in its cell is still drawn from
/// more pixels than it covers.
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
        frame(index(clip, at: elapsed, tempo: tempo))
    }

    /// Which of the atlas's frames is `elapsed` seconds into a clip, looping.
    func index(_ clip: PuffleClip, at elapsed: TimeInterval, tempo: Double = 1) -> Int {
        guard let frames = variant.frames(clip), frames.count > 0 else { return variant.still }
        let step = Int((max(elapsed, 0) * frames.fps * tempo).rounded(.down))
        return frames.start + step % frames.count
    }

    private var resampled: [Int64: CGImage] = [:]

    /// The `index`th frame resampled once, with high-quality filtering, to
    /// exactly `pixels` device pixels a side, so the screen draws it 1:1 and
    /// nothing is ever stretched by the compositor.
    func frame(_ index: Int, pixels: Int) -> CGImage? {
        guard pixels > 0 else { return nil }
        if pixels == cell { return frame(index) }
        let key = Int64(index) << 16 | Int64(pixels)
        if let image = resampled[key] { return image }
        guard let source = frame(index),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let image = context.makeImage()
        resampled[key] = image
        return image
    }
}

/// Where a puffle goes in the box it is drawn in, so the puffle is the same
/// size in every clip — asleep, mid-spin or eating — and as big as the box
/// allows.
///
/// The atlases scale each clip by its own body, but a sleeping puffle under
/// its Zs, one with a thought bubble or one whose motion fills the cell came
/// out much smaller in its cell than the idle one. `measure_bodies.py`
/// measured them — by the puffle's area, so the orange puffle's spiky hair
/// does not count as body — and here every clip is scaled so its puffle is
/// `bodyFill` of the box's height, unless that would cut the puffle off
/// somewhere in the clip's motion; then as close to it as fits. Props, Zs
/// and bubbles may run off the box: across, they are cut at its edges, so
/// they never spill onto the next mark.
struct PuffleLayout: Equatable, Sendable {
    /// Points per large-atlas pixel.
    let scale: CGFloat
    /// Where the cell's top-left corner goes, from the box's top left.
    let origin: CGPoint
    /// How big the puffle comes out, in points: the side of a square of
    /// its area, the measure `measure_bodies.py` takes.
    let bodySize: CGFloat

    /// The puffle's size (the side of a square of its area) against the
    /// box's height. The menu bar's 22 points give it 14.6, which is a
    /// classic puffle 15.8 points tall: a spin, the tallest motion most
    /// puffles have, then still fits the bar within `tolerance`.
    static let bodyFill: CGFloat = 14.6 / 22.0
    /// The box a puffle has in the menu bar: wider than tall, so a puffle
    /// on its side or under its Zs keeps its size.
    static let menuBar = CGSize(width: 28, height: 22)
    /// How far below the resting size a clip may come out before it is left
    /// out of the menu bar's rotation.
    static let tolerance: CGFloat = 0.1
    /// How much a frame may be enlarged on screen, against the atlas's own
    /// pixels at 2x. Above it a clip would be soft, so it is drawn smaller.
    static let maxUpscale: CGFloat = 1.15

    static func layout(_ metrics: PuffleBodyMetrics?, idle: PuffleBodyMetrics?, cell: Int,
                       in canvas: CGSize, displayScale: CGFloat = 2) -> PuffleLayout {
        let side = CGFloat(cell)
        guard let metrics, metrics.body > 0 else {
            // Unmeasured: the whole cell fitted to the box, as it always was.
            let s = min(canvas.width, canvas.height) / side
            return PuffleLayout(scale: s, origin: CGPoint(x: (canvas.width - side * s) / 2,
                                                          y: (canvas.height - side * s) / 2),
                                bodySize: side * 0.68 * s)
        }
        let idle = idle ?? metrics
        let restScale = scale(for: idle, cell: side, canvas: canvas, displayScale: displayScale, cap: nil)
        let s = scale(for: metrics, cell: side, canvas: canvas, displayScale: displayScale, cap: restScale)
        // The floor where the idle puffle, centred in the box, stands; a
        // clip whose motion needs more room above stands lower.
        let rest = CGFloat(idle.bodyBox[3] - idle.bodyBox[1]) * restScale
        let ground = canvas.height - (canvas.height - rest) / 2
        let tall = CGFloat(metrics.bodyBox[3] - metrics.bodyBox[1]) * s
        let floor = min(canvas.height, max(ground, tall))
        let x = canvas.width / 2 - side / 2 * s
        let y = floor - CGFloat(metrics.bodyBox[3]) * s
        return PuffleLayout(scale: s, origin: CGPoint(x: x, y: y), bodySize: CGFloat(metrics.body) * s)
    }

    private static func scale(for m: PuffleBodyMetrics, cell side: CGFloat, canvas: CGSize,
                              displayScale: CGFloat, cap rest: CGFloat?) -> CGFloat {
        var s = canvas.height * bodyFill / CGFloat(m.body)
        // The puffle, wherever it goes in the clip, inside the box's height…
        s = min(s, canvas.height / CGFloat(max(m.bodyBox[3] - m.bodyBox[1], 1)))
        // …and inside its width, centred. Props and Zs are cut at the edges.
        let half = CGFloat(max(side / 2 - m.bodyBox[0], m.bodyBox[2] - side / 2, 1))
        s = min(s, canvas.width / 2 / half)
        // Never enlarged past what stays sharp — or, where even the resting
        // puffle is enlarged, past what it is.
        if let rest { s = min(s, max(maxUpscale / displayScale, rest)) }
        return s
    }

    /// The layout of a clip of a variant's, or of its still frame.
    static func layout(_ clip: PuffleClip?, of variant: PuffleVariant, in canvas: CGSize,
                       displayScale: CGFloat = 2) -> PuffleLayout {
        let metrics = clip.map { variant.frames($0)?.metrics } ?? variant.stillMetrics
        return layout(metrics, idle: variant.frames(.idle)?.metrics, cell: variant.large,
                      in: canvas, displayScale: displayScale)
    }

    /// Whether a clip comes out at the resting size in the menu bar, give or
    /// take `tolerance`. One that cannot — a bubble or a prop that dwarfs
    /// the puffle — is left out of the bar's rotation.
    static func fitsMenuBar(_ clip: PuffleClip, of variant: PuffleVariant) -> Bool {
        guard variant.frames(clip)?.metrics != nil else { return true }
        let rest = menuBar.height * bodyFill
        return layout(clip, of: variant, in: menuBar).bodySize >= rest * (1 - tolerance) - 0.01
    }
}

/// What a puffle rotates through in each mood, from what its SWFs gave it.
///
/// Three programmes, and the limit decides which:
///
/// - **Waiting** — idle, between turns, waiting on a person: a calm, varied
///   round of everything the puffle can do on the spot or on a stroll.
/// - **Working** — a turn in flight: its tricks, one after another.
/// - **Tired** — 75 % of the limit gone: mostly dozing, sleeping and yawning,
///   now and then a calm clip; and at 100 %, asleep.
///
/// **Asleep means the limit.** The sleepy clips (`PuffleClip.sleepy`) are
/// only ever dealt from 75 % of the limit up, and to a working puffle only
/// once it is spent: an agent that is thinking never shows a sleeping mark.
///
/// A clip the variant does not have is left out, and so is one that cannot
/// be drawn at the puffle's size in the menu bar (`PuffleLayout`); a mood
/// left with nothing falls back to the idle blink, which every puffle has.
enum PuffleChoreography {
    typealias Wanted = [(PuffleClip, Double, ClosedRange<TimeInterval>)]

    /// Between turns: never asleep, never the same twice running.
    static let waiting: Wanted = [
        (.idle, 2.5, 4...7), (.look, 2.5, 3...6), (.bounce, 2, 3...5), (.walk, 2, 3...5),
        (.walkSide, 2, 3...5), (.nuzzle, 2, 3...5), (.speak, 1.5, 2...4), (.roll, 1.5, 3...5),
        (.eat, 1.5, 3...5), (.jump, 1.2, 3...4), (.headstand, 0.8, 3...5), (.splash, 0.8, 3...4),
        (.dig, 0.6, 4...6)
    ]

    /// A turn in flight: the energetic tricks.
    static let working: Wanted = [
        (.spin, 2, 2...4), (.jump, 2, 3...4), (.dig, 2, 4...6), (.lift, 2, 4...6),
        (.splash, 1.5, 3...4), (.roll, 2, 3...5), (.walk, 1.5, 3...5), (.walkSide, 1.5, 3...5),
        (.headstand, 1.5, 3...5), (.speak, 1.2, 2...4), (.bounce, 1.2, 3...4)
    ]

    /// Three quarters of the limit gone: nodding off, with the odd calm clip.
    static let tired: Wanted = [
        (.doze, 4, 5...8), (.yawn, 3, 5...7), (.sleep, 3, 8...14), (.look, 0.8, 3...4),
        (.idle, 0.8, 3...5), (.nuzzle, 0.6, 3...4), (.eat, 0.6, 3...5)
    ]

    /// Usage at or past which the sleepy clips may be dealt.
    static let sleepyAt = MarkMood.tiredAt

    static func menu(for mood: MarkMood, variant: PuffleVariant,
                     usedFraction: Double? = nil) -> [MarkBeat<PuffleClip>] {
        let used = usedFraction ?? 0
        let spent = used >= 1 || mood == .spent
        let wanted: Wanted = switch mood {
        case .idle, .concerned, .resting, .revived:
            used >= sleepyAt ? tired : waiting
        case .needsYou:
            [(.speak, 4, 3...5), (.look, 2, 3...4)] + waiting
        case .tired, .exhausted:
            tired
        case .asleep:
            spent ? [(.sleep, 6, 20...40), (.doze, 1, 4...6)] : used >= sleepyAt ? tired : waiting
        case .spent:
            [(.sleep, 1, 60...60)]
        case .working, .commandWait:
            spent ? [(.sleep, 1, 20...40)] : working
        case .waking:
            // Getting up for a turn: straight into it, never out of bed.
            [(.bounce, 3, 2...3), (.jump, 2, 2...3)] + working
        case .celebrating:
            [(.spin, 4, 3...5), (.headstand, 2, 3...5), (.jump, 2, 2...4), (.bounce, 2, 2...4),
             (.roll, 1, 3...4), (.walk, 0.5, 2...3)]
        case .error:
            [(.sick, 4, 3...5), (.look, 3, 3...5), (.speak, 2, 2...3), (.idle, 1, 3...4)]
        }
        let sleepy = spent || used >= sleepyAt || mood == .tired || mood == .exhausted
        var seen = Set<PuffleClip>()
        let menu: [MarkBeat<PuffleClip>] = wanted.compactMap { entry in
            guard seen.insert(entry.0).inserted,
                  sleepy || !entry.0.isSleepy,
                  !(mood.isWorking && !spent && entry.0.isSleepy),
                  // Asleep is asleep, whatever size its frames allow.
                  (spent && entry.0 == .sleep) || PuffleLayout.fitsMenuBar(entry.0, of: variant),
                  let frames = variant.frames(entry.0) else { return nil }
            return MarkBeat(entry.0, weight: entry.1, entry.2, loop: frames.loop / mood.tempo)
        }
        if !menu.isEmpty { return menu }
        let idle = variant.frames(.idle)
        return [MarkBeat(.idle, weight: 1, 4...8, loop: idle.map { $0.loop / mood.tempo })]
    }
}

extension MarkMood {
    /// A turn is in flight.
    var isWorking: Bool {
        switch self {
        case .working, .commandWait, .waking, .celebrating: true
        default: false
        }
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
    /// The height of the box it is drawn in, in points.
    let size: CGFloat
    /// The box's width, when it is not square: the menu bar gives a puffle
    /// a little more room across than up.
    var width: CGFloat?
    /// Whatever tells this mark from its neighbours, so they never move in step.
    var seed = ""

    @State private var director = MarkChoreographer<PuffleClip>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    /// How long two clips are faded across.
    static let fade: TimeInterval = 0.3

    private var canvas: CGSize { CGSize(width: width ?? size, height: size) }

    var body: some View {
        let mood = MarkMood.resolve(pose: pose, usedFraction: usedFraction, justReset: justReset)
        // Always the large atlas, drawn down to size: the small one would
        // have to be enlarged for every clip whose puffle is small in it.
        let sheet = PuffleSheet.sheet(variant, large: true)
        Group {
            if reduceMotion {
                still(sheet, mood: mood)
            } else {
                TimelineView(.animation(minimumInterval: Self.interval(for: mood))) { context in
                    animated(sheet, mood: mood, at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .accessibilityHidden(true)
    }

    static func interval(for mood: MarkMood) -> TimeInterval {
        let base: TimeInterval = mood == .asleep || mood == .exhausted || mood == .spent ? 1 / 6.25 : 1 / 12.5
        return ProcessInfo.processInfo.isLowPowerModeEnabled ? base * 2 : base
    }

    @ViewBuilder
    private func still(_ sheet: PuffleSheet, mood: MarkMood) -> some View {
        if mood.isStill || (usedFraction ?? 0) >= 1 {
            image(sheet, index: variant.still, clip: nil)
        } else {
            image(sheet, index: sheet.index(.idle, at: 0), clip: .idle)
        }
    }

    @ViewBuilder
    private func animated(_ sheet: PuffleSheet, mood: MarkMood, at time: TimeInterval) -> some View {
        let cue = director.cueing(mood: mood, variant: variant, usedFraction: usedFraction, seed: seed, at: time)
        let into = time - cue.start
        let fading = cue.previous != nil && into < Self.fade
        ZStack(alignment: .topLeading) {
            if fading, let previous = cue.previous {
                // The old clip held on the frame it was cut at.
                image(sheet, index: sheet.index(previous, at: cue.start - cue.previousStart, tempo: mood.tempo),
                      clip: previous)
                    .opacity(1 - into / Self.fade)
            }
            image(sheet, index: sheet.index(cue.value, at: into, tempo: mood.tempo), clip: cue.value)
                .opacity(fading ? into / Self.fade : 1)
        }
    }

    /// One frame, resampled to the exact pixels it covers and set where
    /// `PuffleLayout` puts it, on whole pixels, so it is as sharp as the
    /// atlas allows. An unknown clip is the still frame's.
    private func image(_ sheet: PuffleSheet, index: Int, clip: PuffleClip?) -> some View {
        let scale = max(displayScale, 1)
        let known = clip.flatMap { variant.frames($0) } != nil ? clip : nil
        let layout = PuffleLayout.layout(known, of: variant, in: canvas, displayScale: scale)
        let pixels = Int((CGFloat(sheet.cell) * layout.scale * scale).rounded())
        let side = CGFloat(pixels) / scale
        let x = (layout.origin.x * scale).rounded() / scale
        let y = (layout.origin.y * scale).rounded() / scale
        return ZStack(alignment: .topLeading) {
            if let frame = sheet.frame(index, pixels: pixels) {
                Image(decorative: frame, scale: scale)
                    .renderingMode(.original)
                    .interpolation(.high)
                    .frame(width: side, height: side)
                    .offset(x: x, y: y)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        // Cut across, never up and down: a prop stops at the mark's edge
        // instead of spilling onto its neighbour; Zs may rise above it.
        .mask { Rectangle().frame(width: canvas.width, height: canvas.height * 3) }
    }
}

extension MarkChoreographer where Value == PuffleClip {
    func cueing(mood: MarkMood, variant: PuffleVariant, usedFraction: Double? = nil, seed: String,
                at time: TimeInterval) -> MarkCue<PuffleClip> {
        seedIfNeeded(variant.id + "|" + seed)
        return cue(mood: mood, menu: PuffleChoreography.menu(for: mood, variant: variant, usedFraction: usedFraction),
                   at: time)
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
                           size: PuffleLayout.menuBar.height, width: PuffleLayout.menuBar.width,
                           seed: "preview-bar")
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
