// The animation engine behind every animated mark: the AI mascots and the
// Club Penguin puffles alike. `UsageStore.mascotPose` says what the agent is
// up to; this turns that, and how much of the limit is gone, into a mood, and
// the mood into a running programme of animations — never the same one twice
// in a row, and never standing still — not even with the limit spent.
import Foundation

/// How an animated mark feels, which decides what it rotates through.
///
/// Fourteen of them, from the pose and the headline limit. See
/// `docs/animaciones.md` for the full table.
enum MarkMood: String, CaseIterable, Sendable {
    /// Nothing going on, under half the limit used.
    case idle
    /// Idle, with half the limit gone: glances about, fidgets.
    case concerned
    /// Three quarters gone: slow, drowsy, sweating.
    case tired
    /// Nine tenths gone: dozing off where it stands.
    case exhausted
    /// The limit is used up: asleep, or failing that nodding off, faded.
    case spent
    /// A turn in flight and the model is spending tokens.
    case working
    /// A turn in flight waiting on tests, a build or another long command.
    case commandWait
    /// A turn waiting for a person: a question, a permission.
    case needsYou
    /// A turn has just started: getting up.
    case waking
    /// A turn has just finished: the celebration.
    case celebrating
    /// The few minutes after a turn: a break, a snack.
    case resting
    /// Nothing for a long while: asleep, breathing, under its Zs.
    case asleep
    /// The turn failed or the session died in the middle of one.
    case error
    /// The limit has just reset: back on its feet.
    case revived

    /// Where usage starts to show in the mood, as fractions of the limit.
    static let concernedAt = 0.5
    static let tiredAt = 0.75
    static let exhaustedAt = 0.9

    /// The mood for a pose and the headline limit.
    ///
    /// Work and the moments around it come first, exactly as the pose says;
    /// usage only colours the time in between, at 50, 75, 90 and 100 %.
    static func resolve(pose: MascotPose, usedFraction: Double?, justReset: Bool = false) -> MarkMood {
        let used = usedFraction ?? 0
        if justReset, !pose.isWorking, pose != .waking, used < 1 { return .revived }
        switch pose {
        case .run, .type, .thinking: return .working
        case .testing, .longCommand: return .commandWait
        case .waking: return .waking
        case .waiting: return .needsYou
        case .celebrate: return .celebrating
        case .coffee: return .resting
        case .error: return .error
        case .spent: return .spent
        case .tired: return used >= exhaustedAt ? .exhausted : .tired
        case .sleep: return used >= 1 ? .spent : .asleep
        case .awake, .stretch, .play: return level(used)
        }
    }

    /// The idle moods by usage alone.
    static func level(_ used: Double) -> MarkMood {
        if used >= 1 { return .spent }
        if used >= exhaustedAt { return .exhausted }
        if used >= tiredAt { return .tired }
        if used >= concernedAt { return .concerned }
        return .idle
    }

    /// The limit is used up: the mark is drawn faded. It still moves —
    /// asleep where it can, breathing slowly where it cannot.
    var isSpent: Bool { self == .spent }

    /// How fast the mood plays its animations, against their own speed.
    var tempo: Double {
        switch self {
        case .tired: 0.8
        case .exhausted, .asleep, .spent: 0.65
        case .working, .celebrating: 1.1
        default: 1
        }
    }
}

/// One animation a mood can pick, how often, and for how long.
struct MarkBeat<Value: Hashable & Sendable>: Sendable {
    let value: Value
    /// Its share of the picks among the beats on offer.
    let weight: Double
    /// How long it plays once picked, in seconds.
    let duration: ClosedRange<TimeInterval>
    /// The length of one loop of the animation, when it has one: a beat is
    /// then held for whole loops, so it is never cut off mid-jump.
    var loop: TimeInterval?

    init(_ value: Value, weight: Double = 1, _ duration: ClosedRange<TimeInterval>, loop: TimeInterval? = nil) {
        self.value = value
        self.weight = weight
        self.duration = duration
        self.loop = loop
    }
}

/// A small, fast, seedable generator, so a mark's programme is the same in
/// every test run and different from its neighbour's.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// What a mark is playing now, and what it played before it, for the
/// cross-fade between the two.
struct MarkCue<Value: Hashable & Sendable>: Equatable, Sendable {
    let value: Value
    /// When it started, on the clock it was asked with.
    let start: TimeInterval
    /// The beat it took over from, while the two are still being faded.
    let previous: Value?
    let previousStart: TimeInterval
}

/// Deals a mark its programme: on each beat's end, a weighted pick of the
/// next one among what the mood offers, never the one just played.
///
/// A class kept in a view's `@State`, asked for the current beat on every
/// frame. Nothing about it is observed — asking never redraws anything.
@MainActor
final class MarkChoreographer<Value: Hashable & Sendable> {
    private var rng: SplitMix64
    private var seeded = false
    private(set) var mood: MarkMood?
    private(set) var current: Value?
    private(set) var start: TimeInterval = 0
    private(set) var end: TimeInterval = 0
    private var previous: Value?
    private var previousStart: TimeInterval = 0
    /// The first beat on the last menu: in a working mood, the pose the
    /// agent's status asked for.
    private var lead: Value?
    /// How many beats have been dealt, for tests.
    private(set) var dealt = 0

    init(seed: UInt64 = 0) {
        rng = SplitMix64(seed: seed)
        seeded = seed != 0
    }

    /// Seeds it from the mark's identity the first time it is asked.
    func seedIfNeeded(_ key: String) {
        guard !seeded else { return }
        rng = SplitMix64(seed: StableHash.fnv1a(key) | 1)
        seeded = true
    }

    /// The beat to show at `time`. A change of mood cuts the beat short:
    /// news about the agent is never kept waiting for an animation to end.
    func cue(mood: MarkMood, menu: [MarkBeat<Value>], at time: TimeInterval) -> MarkCue<Value> {
        precondition(!menu.isEmpty, "a mood must offer at least one beat")
        let first = menu[0]
        let moodChanged = mood != self.mood
        let stale = current.map { value in !menu.contains { $0.value == value } } ?? true
        // Reading → editing, within one working mood, is news too.
        let ledElsewhere = first.value != lead
        if moodChanged || stale {
            // A new mood opens on its lead beat — the celebration's spin, the
            // pose the status asked for — unless that is what is showing.
            if first.value != current { take(first, at: time) } else { deal(menu, at: time, after: nil) }
        } else if ledElsewhere {
            if first.value != current { take(first, at: time) }
        } else if time >= end || time < start {
            deal(menu, at: time, after: end)
        }
        lead = first.value
        self.mood = mood
        return MarkCue(value: current ?? first.value, start: start,
                       previous: previous, previousStart: previousStart)
    }

    /// The last few beats dealt, newest last, so a long menu goes round
    /// before anything comes back.
    private var recent: [Value] = []

    /// How many of the last beats a menu of `count` keeps out besides the
    /// current one: none for a short menu, up to four for a long one.
    static func memory(for count: Int) -> Int { max(0, min(4, count / 3)) }

    private func deal(_ menu: [MarkBeat<Value>], at time: TimeInterval, after boundary: TimeInterval?) {
        // The one showing is the newest of `recent`; the memory goes back
        // that many more.
        var held = Set(recent.suffix(Self.memory(for: menu.count) + 1))
        if let current { held.insert(current) }
        let fresh = menu.filter { !held.contains($0.value) }
        let options = fresh.isEmpty ? (menu.count > 1 ? menu.filter { $0.value != current } : menu) : fresh
        let beat = Self.pick(options, using: &rng)
        previous = current
        previousStart = start
        // Back to back on the old beat's own clock when it simply ran out, so
        // a frame that came late does not shorten the next one; from now when
        // it was cut short, or when the clock jumped.
        let begin = boundary.map { (0..<1).contains(time - $0) ? $0 : time } ?? time
        start = begin
        end = begin + Self.length(of: beat, using: &rng)
        current = beat.value
        remember(beat.value)
        dealt += 1
    }

    private func remember(_ value: Value) {
        recent.append(value)
        if recent.count > 8 { recent.removeFirst(recent.count - 8) }
    }

    /// Cuts straight to one beat, for news that names it.
    private func take(_ beat: MarkBeat<Value>, at time: TimeInterval) {
        previous = current
        previousStart = start
        start = time
        end = time + Self.length(of: beat, using: &rng)
        current = beat.value
        remember(beat.value)
        dealt += 1
    }

    static func pick(_ options: [MarkBeat<Value>], using rng: inout SplitMix64) -> MarkBeat<Value> {
        let total = options.reduce(0) { $0 + max($1.weight, 0) }
        guard total > 0 else { return options[0] }
        var roll = Double.random(in: 0..<total, using: &rng)
        for option in options {
            roll -= max(option.weight, 0)
            if roll < 0 { return option }
        }
        return options[options.count - 1]
    }

    static func length(of beat: MarkBeat<Value>, using rng: inout SplitMix64) -> TimeInterval {
        let lower = beat.duration.lowerBound, upper = beat.duration.upperBound
        let raw = upper > lower ? Double.random(in: lower...upper, using: &rng) : lower
        guard let loop = beat.loop, loop > 0 else { return max(raw, 0.5) }
        return max(1, (raw / loop).rounded(.up)) * loop
    }
}

/// What the AI mascots — Clawd, the vector characters, the bot and the
/// animated logos — rotate through in each mood. They are drawn by pose, so a
/// beat is a pose.
///
/// **Work keeps its meaning.** In a working mood the pose the agent's status
/// asked for is most of the programme, broken up by the other working poses;
/// an idle mood never picks one, so a mark at the laptop always means a turn
/// in flight.
enum MascotChoreography {
    static func menu(for mood: MarkMood, pose: MascotPose) -> [MarkBeat<MascotPose>] {
        switch mood {
        case .idle:
            [MarkBeat(.awake, weight: 3, 6...12), MarkBeat(.stretch, weight: 2, 4...7),
             MarkBeat(.play, weight: 2, 6...10), MarkBeat(.coffee, weight: 1, 6...10)]
        case .concerned:
            [MarkBeat(.awake, weight: 3, 5...9), MarkBeat(.stretch, weight: 1, 4...6),
             MarkBeat(.tired, weight: 1.5, 3...5), MarkBeat(.play, weight: 1, 5...8)]
        case .tired:
            [MarkBeat(.tired, weight: 4, 8...14), MarkBeat(.stretch, weight: 1, 4...6),
             MarkBeat(.coffee, weight: 1, 6...9)]
        case .exhausted:
            [MarkBeat(.tired, weight: 3, 8...14), MarkBeat(.sleep, weight: 1.5, 5...9)]
        case .spent:
            [MarkBeat(.spent, weight: 3, 10...20), MarkBeat(.sleep, weight: 2, 10...20)]
        case .working:
            [MarkBeat(pose, weight: 4, 8...16)] + [MascotPose.type, .run, .thinking]
                .filter { $0 != pose }
                .map { MarkBeat($0, weight: 1, 3...5) }
        case .commandWait:
            [MarkBeat(pose, weight: 4, 8...14), MarkBeat(.thinking, weight: 1, 3...5)]
        case .needsYou:
            [MarkBeat(.waiting, weight: 4, 6...10), MarkBeat(.awake, weight: 1, 2...3)]
        case .waking:
            [MarkBeat(.waking, 3...3)]
        case .celebrating:
            [MarkBeat(.celebrate, weight: 4, 5...8), MarkBeat(.play, weight: 1, 3...4)]
        case .resting:
            [MarkBeat(.coffee, weight: 4, 8...14), MarkBeat(.stretch, weight: 1, 4...6),
             MarkBeat(.awake, weight: 1, 4...6)]
        case .asleep:
            [MarkBeat(.sleep, weight: 6, 20...40), MarkBeat(.awake, weight: 0.5, 2...3)]
        case .error:
            [MarkBeat(.error, weight: 4, 6...10), MarkBeat(.tired, weight: 1, 3...4)]
        case .revived:
            [MarkBeat(.celebrate, weight: 2, 4...6), MarkBeat(.waking, weight: 1, 3...3),
             MarkBeat(.play, weight: 1, 4...6)]
        }
    }
}
