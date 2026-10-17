// Star Buddy, Float Bot and Cloud Ghost: Antigravity's and Codex's marks,
// drawn in a Canvas from the approved SVGs in design/mascotas (64 × 64 view
// box) rather than shipped as images, so every pose is the same drawing moved,
// and each scales from a 20 pt menu-bar mark to the dock's ring.
import SwiftUI

struct VectorMascotView: View {
    let character: MascotCharacter
    let pose: MascotPose
    /// In the character's own colours, rather than the ink of the surface
    /// behind it — the same choice Clawd makes.
    var colour = true
    let size: CGFloat
    /// Seconds the clock is set ahead, so two marks do not move in lockstep.
    var phase: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, canvasSize in
                    VectorMascots.draw(character, pose: pose, time: 0, colour: colour,
                                       in: &context, size: canvasSize)
                }
            } else {
                TimelineView(.animation(minimumInterval: VectorMascots.interval(for: pose))) { timeline in
                    Canvas { context, canvasSize in
                        VectorMascots.draw(character, pose: pose,
                                           time: timeline.date.timeIntervalSinceReferenceDate + phase,
                                           colour: colour, in: &context, size: canvasSize)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum VectorMascots {
    /// A resting pose is redrawn slowly; a busy one at a pace that reads.
    static func interval(for pose: MascotPose) -> TimeInterval {
        switch pose {
        case .sleep, .tired, .error: 1.0 / 12
        // Fast enough that a blink or a glance is a movement, not a cut.
        case .awake, .stretch: 1.0 / 20
        default: 1.0 / 24
        }
    }

    /// A still, for the menu's session rows.
    @MainActor
    static func image(_ character: MascotCharacter, pose: MascotPose, size: CGFloat, colour: Bool) -> NSImage? {
        let renderer = ImageRenderer(content:
            Canvas(rendersAsynchronously: false) { context, canvasSize in
                draw(character, pose: pose, time: 1.2, colour: colour, in: &context, size: canvasSize)
            }
            .frame(width: size, height: size)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = !colour
        return image
    }

    // MARK: - The pose as numbers

    enum Eyes: Equatable {
        case open(look: CGPoint)
        case closed
        case half
        case happy
        case wide(look: CGPoint)
        case cross
        case squeezed
        /// Codex's `>_` prompt, the cursor blinking. `look` is how far it glances.
        case prompt(cursor: Bool, look: CGPoint)
    }

    enum Mouth: Equatable { case smile, flat, small, open, frown }

    /// Where the body is and what the face says at one moment of a pose.
    struct Moment {
        var offset = CGSize.zero
        var rotation = 0.0
        var scale = CGSize(width: 1, height: 1)
        /// Scaled about the feet rather than the middle: landing, rising.
        var fromFeet = false
        var eyes = Eyes.open(look: .zero)
        /// How far a blink has the open eyes (or Codex's `>`) shut, 0 to 1.
        var lid = 0.0
        var mouth = Mouth.smile
        var grey = false
    }

    /// `gain` widens the motion for a mark drawn small: a two-unit bob is half
    /// a pixel at menu-bar size, which is no bob at all.
    static func moment(for pose: MascotPose, character: MascotCharacter, at time: TimeInterval,
                       gain: Double = 1) -> Moment {
        var moment = momentAtFullGain(for: pose, character: character, at: time)
        guard gain != 1 else { return moment }
        moment.offset = CGSize(width: moment.offset.width * gain, height: moment.offset.height * gain)
        // Wider, but never a tilt that reads as a different shape.
        moment.rotation = max(-10, min(10, moment.rotation * gain))
        moment.scale = CGSize(width: 1 + (moment.scale.width - 1) * gain, height: 1 + (moment.scale.height - 1) * gain)
        if character == .cloudGhost { keepCloudInFrame(&moment) }
        return moment
    }

    /// The cloud fills its box nearly edge to edge, so the widened motion a
    /// small mark needs would flatten it into a pill and push it out of the
    /// frame. A pillow gives a little, never more: it stays round and whole.
    private static func keepCloudInFrame(_ moment: inout Moment) {
        moment.scale = CGSize(width: min(1.06, max(0.96, moment.scale.width)),
                              height: min(1.07, max(0.91, moment.scale.height)))
        moment.offset = CGSize(width: min(2.2, max(-2.2, moment.offset.width)),
                               height: min(2.4, max(-3.4, moment.offset.height)))
        moment.rotation = min(6, max(-6, moment.rotation))
    }

    // MARK: - Beats
    //
    // Clawd holds a frame, then the next; the bot eases a squash into a landing.
    // These marks do the same kind of acting, each in its own weight: the arch
    // is nearly weightless, the cloud is a pillow, the star is a buoy.
    //
    // Every curve here ends where it starts and has no corner at the seam, so
    // a loop never pops. The uneven beats (blinks, glances, keystrokes) come
    // from a hash of the clock: nothing is allocated or remembered between
    // frames, and the same moment always draws the same picture, which keeps
    // the menu's stills and the tests steady.

    private static func wrap(_ time: TimeInterval, _ period: Double) -> Double {
        let turned = time.truncatingRemainder(dividingBy: period)
        return (turned < 0 ? turned + period : turned) / period
    }

    private static func smooth(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return t * t * (3 - 2 * t)
    }

    private static func easeOutCubic(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        let u = 1 - t
        return 1 - u * u * u
    }

    /// Past the end and back: a catch, a snap upright. Flat at both ends.
    private static func easeOutBack(_ t: Double, overshoot: Double = 1.4) -> Double {
        let u = min(1, max(0, t)) - 1
        return 1 + (overshoot + 1) * u * u * u + overshoot * u * u
    }

    private static func mix(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        CGPoint(x: mix(a.x, b.x, u), y: mix(a.y, b.y, u))
    }

    private static func mix(_ a: CGSize, _ b: CGSize, _ u: Double) -> CGSize {
        CGSize(width: mix(a.width, b.width, u), height: mix(a.height, b.height, u))
    }

    /// 0 before `from`, 1 after `to`, eased between.
    private static func ramp(_ t: Double, _ from: Double, _ to: Double) -> Double {
        smooth((t - from) / (to - from))
    }

    /// Up between `a` and `b`, held, down between `c` and `d`.
    private static func hold(_ t: Double, _ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        ramp(t, a, b) * (1 - ramp(t, c, d))
    }

    private static func sine(_ time: TimeInterval, _ period: Double, _ shift: Double = 0) -> Double {
        sin(wrap(time, period) * 2 * .pi + shift)
    }

    /// A steady number in [0, 1) for one slot of time (SplitMix64).
    private static func noise(_ slot: Int, _ salt: UInt64) -> Double {
        var z = UInt64(bitPattern: Int64(slot)) &+ (salt &+ 1) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / 9_007_199_254_740_992
    }

    /// Which slot of `length` seconds the clock is in, and how far into it.
    private static func slot(_ time: TimeInterval, _ length: Double) -> (index: Int, into: Double) {
        let index = (time / length).rounded(.down)
        return (Int(index), time - index * length)
    }

    /// How shut the eyes are, 0 to 1. Quick to close, slower to open, and
    /// never on a metronome: each 1.5 s slot holds a blink about half the
    /// time, now and then a double. The first slot never blinks, so a still
    /// drawn at a fixed early moment has its eyes open.
    private static func blinkLid(_ time: TimeInterval, salt: UInt64) -> Double {
        let (index, into) = slot(time, 1.5)
        guard index != 0 else { return 0 }
        let roll = noise(index, salt)
        guard roll < 0.5 else { return 0 }
        let start = 0.1 + 0.8 * noise(index, salt &+ 1)
        let lid = lidCurve(into - start)
        return roll < 0.1 ? max(lid, lidCurve(into - start - 0.34)) : lid
    }

    private static func lidCurve(_ t: Double) -> Double {
        guard t > 0, t < 0.26 else { return 0 }
        if t < 0.07 { return smooth(t / 0.07) }
        if t < 0.14 { return 1 }
        return 1 - smooth((t - 0.14) / 0.12)
    }

    /// A terminal cursor: lit longer than dark, and quicker while keys are going.
    private static func cursorLit(_ time: TimeInterval, typing: Bool) -> Bool {
        let period = typing ? 0.70 : 1.06
        let lit = typing ? 0.42 : 0.68
        return wrap(time, period) * period < lit
    }

    /// Where idle eyes rest: mostly ahead, now and then a look somewhere
    /// within `reach`, a new choice every `every` seconds, moved to quickly.
    private static func glance(_ time: TimeInterval, every: Double, reach: CGPoint, salt: UInt64) -> CGPoint {
        let (index, into) = slot(time, every)
        func target(_ k: Int) -> CGPoint {
            guard k != 0, noise(k, salt) >= 0.4 else { return .zero }
            return CGPoint(x: (2 * noise(k, salt &+ 2) - 1) * reach.x,
                           y: (2 * noise(k, salt &+ 3) - 1) * reach.y)
        }
        return mix(target(index - 1), target(index), smooth(into / 0.22))
    }

    /// A float, 0 at the bottom and 1 at the top, with no corner at either
    /// end; `linger` keeps it near the top a little longer.
    private static func bob(_ time: TimeInterval, period: Double, linger: Double = 0.5) -> Double {
        let b = 0.5 - 0.5 * cos(wrap(time, period) * 2 * .pi)
        return mix(b, b * (2 - b), linger)
    }

    /// Which way a `bob` of the same period is heading: 1 rising, -1 falling.
    private static func rising(_ time: TimeInterval, period: Double) -> Double {
        sine(time, period)
    }

    /// A hop that loops. On the ground it sinks and pushes off — one smooth
    /// dip, widest at the bottom — then it flies, stretched on the way up and
    /// down and round at the crest. Height is 0 on the ground, 1 at the crest
    /// and negative in the dip; squash is positive when wide and short.
    /// `weight` is 0 for something with no mass and 1 for a pillow; `hang`
    /// holds it at the crest.
    private static func bounce(_ time: TimeInterval, period: Double, hang: Double,
                               weight: Double) -> (height: Double, squash: Double) {
        let t = wrap(time, period)
        let ground = 0.16 + 0.14 * weight
        if t < ground {
            let dip = sin(t / ground * .pi)
            return (-0.22 * weight * dip, (0.05 + 0.07 * weight) * dip)
        }
        let air = (t - ground) / (1 - ground)
        let arc = sin(air * .pi)
        let height = mix(arc, arc * (2 - arc), min(1, 2.5 * hang))
        let speed = sin(air * 2 * .pi)
        return (height, -(0.03 + 0.025 * (1 - weight)) * speed * speed)
    }

    /// Longer in than out. 0 empty, 1 full.
    private static func breath(_ time: TimeInterval, period: Double = 3.6) -> Double {
        let t = wrap(time, period)
        if t < 0.62 { return smooth(t / 0.62) }
        return 1 - smooth((t - 0.62) / 0.38)
    }

    /// Keystrokes: a quick press and a softer release, each its own weight,
    /// one beat in five or so skipped. 0 at rest, 1 pressed hard.
    private static func keystrokes(_ time: TimeInterval, beat: Double, salt: UInt64) -> Double {
        let (index, into) = slot(time, beat)
        guard noise(index, salt) < 0.8 else { return 0 }
        let t = into / beat
        let press = t < 0.25 ? easeOutCubic(t / 0.25) : 1 - smooth((t - 0.25) / 0.75)
        return (0.6 + 0.4 * noise(index, salt &+ 1)) * press
    }

    /// The cup's beat, as Clawd's: steam, steam, then a sip. 0 at rest, 1
    /// with the cup up.
    private static func sip(_ time: TimeInterval) -> Double {
        hold(wrap(time, 4.2), 0.48, 0.55, 0.64, 0.72)
    }

    /// Nodding off: a slow sink, then a catch that snaps a little past upright.
    /// 0 upright, 1 at the deepest.
    private static func nod(_ time: TimeInterval, period: Double) -> Double {
        let t = wrap(time, period)
        if t < 0.74 { let u = smooth(t / 0.74); return u * u }
        return 1 - easeOutBack((t - 0.74) / 0.26)
    }

    /// Leaning in for a closer look at the test tube, once every three
    /// bubbles. 0 back, 1 close.
    private static func peer(_ time: TimeInterval) -> Double {
        hold(wrap(time, 3.3), 0.30, 0.45, 0.72, 0.92)
    }

    /// A stretch: a small crouch to wind up, a long reach held with a
    /// tremble, then a sigh back to rest. -0.4 crouched, 1 at full reach.
    private static func stretchReach(_ time: TimeInterval, period: Double) -> Double {
        let t = wrap(time, period)
        if t < 0.16 { return -0.4 * smooth(t / 0.16) }
        if t < 0.52 { return -0.4 + 1.4 * smooth((t - 0.16) / 0.36) }
        if t < 0.70 { return 1 - 0.03 * sin((t - 0.52) / 0.18 * 4 * .pi) }
        return 1 - smooth((t - 0.70) / 0.30)
    }

    /// The foot that taps while a long command runs, in time with the
    /// hourglass beside it (`drawHourglass`, a 4 s glass), and the start it
    /// gives when the glass turns over.
    private static func impatience(_ time: TimeInterval) -> (tap: Double, flip: Double) {
        let cycle = wrap(time, 4)
        guard cycle < 0.875 else { return (0, sin((cycle - 0.875) / 0.125 * .pi)) }
        let t = wrap(time, 0.5)
        return (t < 0.2 ? easeOutCubic(t / 0.2) : 1 - smooth((t - 0.2) / 0.4), 0)
    }

    /// Spent: a slow woozy circle, with a shiver every couple of seconds.
    private static func dizzy(_ time: TimeInterval, period: Double) -> (x: Double, y: Double, shiver: Double) {
        let turn = wrap(time, period) * 2 * .pi
        let burst = hold(wrap(time, 2.4), 0, 0.05, 0.13, 0.2)
        return (cos(turn), sin(turn), burst * sin(time * 44))
    }

    /// Getting up, in the three beats Clawd uses — crouched, half open, up
    /// with a spring — then settling back into the crouch, so the loop has no
    /// seam. `depth` is how low the crouch goes and `lift` how high it springs.
    private static func wakeUp(_ time: TimeInterval, depth: Double, lift: Double, awake: Eyes,
                               into moment: inout Moment) {
        let beat = wrap(time, 3) * 3
        let crouch = CGSize(width: 1 + 0.4 * depth, height: 1 - depth)
        let half = CGSize(width: 1 + 0.2 * depth, height: 1 - 0.5 * depth)
        let spring = CGSize(width: 1 - 0.2 * depth, height: 1 + 0.4 * depth)
        let rest = CGSize(width: 1, height: 1)
        moment.fromFeet = true
        moment.lid = 0
        if beat < 1 {
            let air = sin(beat * .pi)
            moment.scale = CGSize(width: crouch.width - 0.01 * air, height: crouch.height + 0.025 * air)
            moment.eyes = .closed
            moment.mouth = .small
        } else if beat < 1.7 {
            let u = ramp(beat, 1, 1.7)
            moment.scale = mix(crouch, half, u)
            moment.offset.height = -0.2 * lift * u
            moment.eyes = .half
            moment.mouth = .small
        } else if beat < 2 {
            let u = easeOutCubic((beat - 1.7) / 0.3)
            moment.scale = mix(half, spring, u)
            moment.offset.height = mix(-0.2 * lift, -lift, u)
            moment.eyes = awake
            moment.mouth = .open
        } else if beat < 2.6 {
            let u = ramp(beat, 2, 2.6)
            moment.scale = mix(spring, rest, u)
            moment.offset.height = mix(-lift, -0.7 * lift, u)
            moment.eyes = awake
            moment.mouth = .open
        } else {
            let u = ramp(beat, 2.6, 3)
            moment.scale = mix(rest, crouch, u)
            moment.offset.height = mix(-0.7 * lift, 0, u)
            moment.eyes = u < 0.5 ? .half : .closed
            moment.mouth = .small
        }
    }

    private static func momentAtFullGain(for pose: MascotPose, character: MascotCharacter, at time: TimeInterval) -> Moment {
        switch character {
        case .cloudGhost: codexMoment(pose, at: time)
        case .starBuddy: starMoment(pose, at: time)
        default: antigravityMoment(pose, at: time)
        }
    }

    /// Float Bot: almost no weight. It hangs in the air and tilts like
    /// something curious; landings are light and the hops hang long.
    private static func antigravityMoment(_ pose: MascotPose, at time: TimeInterval) -> Moment {
        var moment = Moment()
        moment.lid = blinkLid(time, salt: 11)
        switch pose {
        case .awake:
            let up = bob(time, period: 2.8, linger: 0.6)
            let lift = rising(time, period: 2.8)
            moment.fromFeet = true
            moment.offset.height = -2.0 * up
            moment.rotation = 2.0 * sine(time, 5.6)
            moment.scale = CGSize(width: 1 + 0.02 * (1 - up) - 0.02 * lift,
                                  height: 1 - 0.025 * (1 - up) + 0.035 * lift)
            moment.eyes = .open(look: glance(time, every: 2.3, reach: CGPoint(x: 1.4, y: 0.9), salt: 12))
            moment.mouth = .smile
        case .run:
            let jump = bounce(time, period: 0.48, hang: 0.30, weight: 0.15)
            moment.fromFeet = true
            moment.offset.height = -3.6 * max(0, jump.height)
            moment.rotation = -7 - 2.5 * max(0, jump.height)
            moment.scale = CGSize(width: 1 + jump.squash, height: 1 - jump.squash)
            moment.eyes = .open(look: CGPoint(x: 1.5, y: -0.15))
            moment.lid = 0
            moment.mouth = .flat
        case .type:
            let key = keystrokes(time, beat: 0.16, salt: 13)
            let read = 0.5 - 0.5 * cos(wrap(time, 3.2) * 2 * .pi)
            moment.fromFeet = true
            moment.offset.height = 0.7 * key - 0.5 * bob(time, period: 1.6)
            moment.rotation = 2.4 * sine(time, 3.2)
            moment.scale = CGSize(width: 1 + 0.045 * key, height: 1 - 0.055 * key)
            moment.eyes = .open(look: CGPoint(x: -1.6 + 1.2 * read, y: 0.7))
            moment.mouth = .flat
        case .thinking:
            // Up and away to ponder, back to the middle, a glance the other way.
            let beat = wrap(time, 3.4)
            let ponder = CGPoint(x: 1.35, y: -1.35), back = CGPoint(x: 0.15, y: -0.35)
            let aside = CGPoint(x: -0.9, y: -0.5)
            let look = beat < 0.5 ? mix(aside, ponder, ramp(beat, 0, 0.06))
                : beat < 0.78 ? mix(ponder, back, ramp(beat, 0.5, 0.56))
                : mix(back, aside, ramp(beat, 0.78, 0.84))
            let up = bob(time, period: 3.4, linger: 0.7)
            moment.rotation = -6.5 + 2.4 * sine(time, 6.8)
            moment.offset.height = -1.6 * up
            moment.offset.width = 0.6 * sine(time, 6.8, 1)
            moment.scale = CGSize(width: 1 - 0.015 * up, height: 1 + 0.025 * up)
            moment.eyes = .open(look: look)
            moment.mouth = .small
        case .waking:
            wakeUp(time, depth: 0.2, lift: 1.8, awake: .wide(look: .zero), into: &moment)
        case .waiting:
            let jump = bounce(time, period: 0.92, hang: 0.34, weight: 0.12)
            moment.fromFeet = true
            moment.offset.height = -4.6 * max(0, jump.height)
            moment.scale = CGSize(width: 1 + jump.squash, height: 1 - jump.squash)
            moment.rotation = 2.4 * sine(time, 1.84)
            moment.eyes = .wide(look: CGPoint(x: 0.5, y: -1.1))
            moment.mouth = .small
        case .celebrate:
            let jump = bounce(time, period: 0.52, hang: 0.22, weight: 0.08)
            moment.fromFeet = true
            moment.offset.height = -5.4 * max(0, jump.height)
            moment.rotation = 8 * sine(time, 1.04) * (0.3 + 0.7 * max(0, jump.height))
            moment.scale = CGSize(width: 1 + jump.squash, height: 1 - jump.squash)
            moment.eyes = .happy
            moment.mouth = .open
        case .coffee:
            let cup = sip(time)
            moment.rotation = 2.6 * sine(time, 4.2) + 3 * cup
            moment.offset.height = -0.8 * bob(time, period: 2.1) - 0.8 * cup
            moment.offset.width = 0.5
            moment.scale = CGSize(width: 1 - 0.02 * cup, height: 1 + 0.03 * cup)
            moment.eyes = cup > 0.5 ? .happy : .open(look: CGPoint(x: 1.1, y: 0.35))
            moment.mouth = cup > 0.5 ? .open : .smile
        case .stretch:
            let reach = stretchReach(time, period: 2.8)
            let up = max(0, reach), down = max(0, -reach)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1 - 0.06 * up + 0.045 * down, height: 1 + 0.10 * up - 0.05 * down)
            moment.offset.height = -0.8 * up
            moment.eyes = up > 0.55 ? .happy : .closed
            moment.mouth = up > 0.55 ? .open : .small
        case .play:
            let across = playAcross(at: time)
            let follow = smooth(across) - 0.5
            let hop = bounce(time, period: 2 / 0.9 / 4, hang: 0.25, weight: 0.1)
            moment.fromFeet = true
            moment.offset.width = 4.4 * follow
            moment.offset.height = -1.9 * max(0, hop.height)
            moment.rotation = 5 * follow
            moment.scale = CGSize(width: 1 + hop.squash, height: 1 - hop.squash)
            moment.eyes = .open(look: CGPoint(x: (across - 0.5) * 2.6, y: -1.1))
            moment.lid = 0
            moment.mouth = .open
        case .sleep:
            let air = breath(time, period: 4.4)
            moment.fromFeet = true
            moment.offset.height = 1.7 - 0.35 * air
            moment.rotation = 1.4 * sine(time, 8.8)
            moment.scale = CGSize(width: 1.02 - 0.03 * air, height: 0.98 + 0.045 * air)
            moment.eyes = .closed
            moment.mouth = .small
        case .tired:
            let air = breath(time, period: 2.8)
            let dip = nod(time, period: 4.6)
            moment.fromFeet = true
            moment.rotation = -6.5 - 3.5 * dip
            moment.offset.height = 1.6 + 1.0 * dip
            moment.scale = CGSize(width: 1.045 - 0.02 * air + 0.02 * dip, height: 0.955 + 0.02 * air - 0.03 * dip)
            moment.eyes = dip > 0.8 ? .closed : .half
            moment.mouth = .flat
        case .spent:
            let woozy = dizzy(time, period: 1.6)
            moment.fromFeet = true
            moment.offset.width = 0.9 * woozy.x + 0.8 * woozy.shiver
            moment.offset.height = 0.6 + 0.5 * woozy.y
            moment.rotation = 4 * woozy.y
            moment.scale = CGSize(width: 1.04, height: 0.96)
            moment.eyes = .squeezed
            moment.mouth = .frown
        case .testing:
            let close = peer(time)
            moment.rotation = -4.2 + 5.5 * close + 1.2 * sine(time, 6.6)
            moment.offset.width = -1.2 + 0.9 * close
            moment.offset.height = -1.1 * bob(time, period: 2.2)
            moment.eyes = close > 0.5 ? .wide(look: CGPoint(x: 1.6, y: -1.2))
                : .open(look: CGPoint(x: 1.45, y: -1.15))
            moment.mouth = .small
        case .longCommand:
            let wait = impatience(time)
            moment.fromFeet = true
            moment.offset.width = -1.2
            moment.offset.height = 0.35 + 0.45 * wait.tap - 2.4 * wait.flip
            moment.rotation = 2.6 * sine(time, 8)
            moment.scale = CGSize(width: 1 + 0.03 * wait.tap - 0.03 * wait.flip,
                                  height: 1 - 0.035 * wait.tap + 0.05 * wait.flip)
            moment.eyes = wait.flip > 0.2 ? .wide(look: CGPoint(x: 1.5, y: -0.6))
                : .open(look: CGPoint(x: 1.3, y: 0.95))
            moment.mouth = wait.flip > 0.2 ? .small : .flat
        case .error:
            let sag = breath(time, period: 2.4)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1.10 + 0.045 * sag, height: 0.84 - 0.045 * sag)
            moment.rotation = -2 + 1.5 * sine(time, 4.8)
            moment.eyes = .cross
            moment.mouth = .frown
            moment.grey = true
        }
        return moment
    }

    /// Cloud Ghost: a pillow. Landings squash and its body catches up a beat
    /// late; the `>_` is the face, and the cursor is what blinks while it is
    /// awake — solid while keys are going, as a terminal's is.
    private static func codexMoment(_ pose: MascotPose, at time: TimeInterval) -> Moment {
        var moment = Moment()
        moment.lid = blinkLid(time, salt: 21)
        func prompt(_ look: CGPoint, typing: Bool = false, held: Bool = false) -> Eyes {
            .prompt(cursor: held || cursorLit(time, typing: typing), look: look)
        }
        switch pose {
        case .awake:
            let up = bob(time, period: 3.6, linger: 0.4)
            let late = bob(time - 0.4, period: 3.6, linger: 0.4)
            moment.offset.height = -1.4 * up
            moment.offset.width = 1.6 * sine(time, 7.2)
            moment.rotation = 1.2 * sine(time, 7.2, 0.8)
            moment.scale = CGSize(width: 1.04 - 0.06 * late, height: 0.965 + 0.07 * late)
            moment.eyes = prompt(glance(time, every: 2.9, reach: CGPoint(x: 1.0, y: 0.6), salt: 22))
            moment.mouth = .smile
        case .run:
            let jump = bounce(time, period: 0.66, hang: 0.14, weight: 0.8)
            moment.fromFeet = true
            moment.offset.height = -2.8 * max(0, jump.height)
            moment.offset.width = 1.2 * sine(time, 2.64)
            moment.rotation = -4.5 - 1.5 * max(0, jump.height)
            moment.scale = CGSize(width: 1 + 1.25 * jump.squash, height: 1 - 1.25 * jump.squash)
            moment.eyes = prompt(CGPoint(x: 1.15, y: 0), typing: true)
            moment.lid = 0
            moment.mouth = .flat
        case .type:
            let key = keystrokes(time, beat: 0.15, salt: 23)
            moment.fromFeet = true
            moment.offset.height = 0.6 * key - 0.4 * bob(time, period: 1.8)
            moment.rotation = 1.8 * sine(time, 2.9)
            moment.scale = CGSize(width: 1 + 0.06 * key, height: 1 - 0.06 * key)
            moment.eyes = prompt(CGPoint(x: -0.75 + 0.45 * key, y: 0.4), typing: true, held: key > 0.15)
            moment.mouth = .flat
        case .thinking:
            let beat = wrap(time, 3.6)
            let up = CGPoint(x: 0.95, y: -0.85), back = CGPoint(x: -0.45, y: -0.25)
            let look = beat < 0.55 ? mix(back, up, ramp(beat, 0, 0.07)) : mix(up, back, ramp(beat, 0.55, 0.62))
            let float = bob(time, period: 3.6, linger: 0.6)
            moment.rotation = -5.5 + 1.8 * sine(time, 7.2)
            moment.offset.height = -1.2 * float
            moment.offset.width = 0.9 * sine(time, 9.6)
            moment.scale = CGSize(width: 1 - 0.015 * float, height: 1 + 0.02 * float)
            moment.eyes = prompt(look)
            moment.mouth = .small
        case .waking:
            wakeUp(time, depth: 0.08, lift: 1.6, awake: prompt(.zero), into: &moment)
        case .waiting:
            let jump = bounce(time, period: 1.08, hang: 0.18, weight: 0.9)
            moment.fromFeet = true
            moment.offset.height = -3.8 * max(0, jump.height)
            moment.scale = CGSize(width: 1 + 1.25 * jump.squash, height: 1 - 1.25 * jump.squash)
            moment.rotation = 1.5 * sine(time, 2.16)
            moment.eyes = prompt(CGPoint(x: 0.45, y: -0.75))
            moment.mouth = .small
        case .celebrate:
            let jump = bounce(time, period: 0.58, hang: 0.16, weight: 0.55)
            moment.fromFeet = true
            moment.offset.height = -4.8 * max(0, jump.height)
            moment.rotation = 6 * sine(time, 1.16) * (0.3 + 0.7 * max(0, jump.height))
            moment.scale = CGSize(width: 1 + 1.1 * jump.squash, height: 1 - 1.1 * jump.squash)
            moment.eyes = .happy
            moment.mouth = .open
        case .coffee:
            let cup = sip(time)
            moment.rotation = 2.4 * sine(time, 8.4) + 2.5 * cup
            moment.offset.width = 0.9 * sine(time, 8.4, 1)
            moment.offset.height = -0.85 * bob(time, period: 2.1) - 0.6 * cup
            moment.scale = CGSize(width: 1.03 - 0.02 * cup, height: 0.98 + 0.03 * cup)
            moment.eyes = cup > 0.5 ? .happy : prompt(CGPoint(x: 0.9, y: 0.3))
            moment.mouth = cup > 0.5 ? .open : .smile
        case .stretch:
            let reach = stretchReach(time, period: 3.1)
            let up = max(0, reach), down = max(0, -reach)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1.04 - 0.08 * up + 0.06 * down, height: 0.98 + 0.12 * up - 0.06 * down)
            moment.eyes = up > 0.55 ? .happy : .closed
            moment.mouth = up > 0.55 ? .open : .small
        case .play:
            let across = playAcross(at: time)
            let follow = smooth(across) - 0.5
            let hop = bounce(time, period: 2 / 0.9 / 3, hang: 0.15, weight: 0.7)
            moment.fromFeet = true
            moment.offset.width = 4.8 * follow
            moment.offset.height = -1.4 * max(0, hop.height)
            moment.rotation = 3 * follow
            moment.scale = CGSize(width: 1.04 + hop.squash, height: 0.97 - hop.squash)
            moment.eyes = prompt(CGPoint(x: (across - 0.5) * 1.8, y: -0.55))
            moment.lid = 0
            moment.mouth = .open
        case .sleep:
            let air = breath(time, period: 4.6)
            moment.fromFeet = true
            moment.offset.height = 3.1 - 0.4 * air
            moment.rotation = 1.2 * sine(time, 9.2)
            moment.scale = CGSize(width: 1.06 - 0.05 * air, height: 0.94 + 0.065 * air)
            moment.eyes = .closed
            moment.mouth = .small
        case .tired:
            let air = breath(time, period: 3.0)
            let dip = nod(time, period: 5.2)
            moment.fromFeet = true
            moment.rotation = -8 - 3 * dip
            moment.offset.height = 2.4 + 0.9 * dip
            moment.scale = CGSize(width: 1.07 - 0.02 * air + 0.02 * dip, height: 0.93 + 0.025 * air - 0.03 * dip)
            moment.eyes = dip > 0.8 ? .closed : .half
            moment.mouth = .flat
        case .spent:
            let woozy = dizzy(time, period: 1.8)
            moment.fromFeet = true
            moment.offset.width = 1.0 * woozy.x + 0.9 * woozy.shiver
            moment.offset.height = 0.6 + 0.4 * woozy.y
            moment.rotation = 3 * woozy.y
            moment.scale = CGSize(width: 1.06, height: 0.93)
            moment.eyes = .squeezed
            moment.mouth = .frown
        case .testing:
            let close = peer(time)
            moment.rotation = -3.5 + 5 * close + 1.0 * sine(time, 7.2)
            moment.offset.width = -1.4 + 0.9 * close
            moment.offset.height = -0.7 * bob(time, period: 2.6)
            moment.eyes = prompt(mix(CGPoint(x: 1.2, y: -0.7), CGPoint(x: 1.6, y: -1.0), close))
            moment.mouth = .small
        case .longCommand:
            let wait = impatience(time)
            moment.fromFeet = true
            moment.offset.width = -1.3
            moment.offset.height = 0.8 + 0.5 * wait.tap - 2.0 * wait.flip
            moment.rotation = 2.2 * sine(time, 8)
            moment.scale = CGSize(width: 1.03 + 0.04 * wait.tap - 0.03 * wait.flip,
                                  height: 0.98 - 0.045 * wait.tap + 0.05 * wait.flip)
            moment.eyes = prompt(wait.flip > 0.2 ? CGPoint(x: 1.3, y: -0.5) : CGPoint(x: 1.05, y: 0.7))
            moment.mouth = .flat
        case .error:
            let sag = breath(time, period: 2.6)
            moment.fromFeet = true
            moment.offset.height = 1.2 + 0.4 * sag
            moment.scale = CGSize(width: 1.04 + 0.02 * sag, height: 0.95 - 0.025 * sag)
            moment.rotation = -2 + 1.2 * sine(time, 5.2)
            moment.eyes = .cross
            moment.mouth = .frown
            moment.grey = true
        }
        return moment
    }

    /// Star Buddy: a buoy. Quicker than the cloud, with a glint in the scale;
    /// it spins when it is pleased and tips over when it sleeps.
    private static func starMoment(_ pose: MascotPose, at time: TimeInterval) -> Moment {
        var moment = Moment()
        moment.lid = blinkLid(time, salt: 31)
        let glint = 0.02 * sine(time, 2 * .pi / 5.5)
        switch pose {
        case .awake:
            let up = bob(time, period: 2.4)
            moment.offset.height = -1.4 * up
            moment.rotation = 2.4 * sine(time, 3.2)
            moment.scale = CGSize(width: 1 + glint, height: 1 + 0.03 * up - glint)
            moment.fromFeet = true
            moment.eyes = .open(look: glance(time, every: 2.1, reach: CGPoint(x: 1.3, y: 0.9), salt: 32))
            moment.mouth = .smile
        case .run:
            let jump = bounce(time, period: 0.42, hang: 0.18, weight: 0.25)
            moment.fromFeet = true
            moment.offset.height = -3.2 * max(0, jump.height)
            moment.rotation = -6 - 2 * max(0, jump.height)
            moment.scale = CGSize(width: 1 + jump.squash + glint, height: 1 - jump.squash)
            moment.eyes = .open(look: CGPoint(x: 1.4, y: 0))
            moment.lid = 0
            moment.mouth = .flat
        case .type:
            let key = keystrokes(time, beat: 0.17, salt: 33)
            let read = 0.5 - 0.5 * cos(wrap(time, 3.1) * 2 * .pi)
            moment.fromFeet = true
            moment.offset.height = 0.7 * key - 0.5 * bob(time, period: 1.7)
            moment.rotation = 3.0 * sine(time, 3.1)
            moment.scale = CGSize(width: 1 + glint + 0.04 * key, height: 1 - 0.05 * key)
            moment.eyes = .open(look: CGPoint(x: -1.4 + 1.0 * read, y: 0.55))
            moment.mouth = .flat
        case .thinking:
            let beat = wrap(time, 3.2)
            let up = CGPoint(x: 1.2, y: -1.2), aside = CGPoint(x: -0.6, y: -1.2)
            let look = beat < 0.6 ? mix(aside, up, ramp(beat, 0, 0.06)) : mix(up, aside, ramp(beat, 0.6, 0.66))
            moment.rotation = -5 + 2 * sine(time, 5.2)
            moment.offset.height = -1.2 * bob(time, period: 2.6, linger: 0.6)
            moment.eyes = .open(look: look)
            moment.mouth = .small
        case .waking:
            wakeUp(time, depth: 0.2, lift: 1.3, awake: .wide(look: .zero), into: &moment)
        case .waiting:
            let jump = bounce(time, period: 0.84, hang: 0.26, weight: 0.3)
            moment.fromFeet = true
            moment.offset.height = -4.4 * max(0, jump.height)
            moment.scale = CGSize(width: 1 + jump.squash, height: 1 - jump.squash)
            moment.rotation = 2 * sine(time, 1.68)
            moment.eyes = .wide(look: CGPoint(x: 0.6, y: -1.0))
            moment.mouth = .small
        case .celebrate:
            let jump = bounce(time, period: 0.48, hang: 0.2, weight: 0.2)
            moment.fromFeet = true
            moment.offset.height = -5.2 * max(0, jump.height)
            moment.rotation = 8 * sine(time, 0.96) * (0.3 + 0.7 * max(0, jump.height))
            moment.scale = CGSize(width: 1 + jump.squash + glint, height: 1 - jump.squash)
            moment.eyes = .happy
            moment.mouth = .open
        case .coffee:
            let cup = sip(time)
            moment.rotation = 2.8 * sine(time, 4.2) + 3 * cup
            moment.offset.height = -0.6 * bob(time, period: 2.1) - 0.7 * cup
            moment.scale = CGSize(width: 1 - 0.02 * cup, height: 1 + 0.03 * cup)
            moment.eyes = cup > 0.5 ? .happy : .open(look: CGPoint(x: 1.0, y: 0.4))
            moment.mouth = cup > 0.5 ? .open : .smile
        case .stretch:
            let reach = stretchReach(time, period: 2.6)
            let up = max(0, reach), down = max(0, -reach)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1 - 0.05 * up + 0.04 * down, height: 1 + 0.09 * up - 0.045 * down)
            moment.eyes = up > 0.55 ? .happy : .closed
            moment.mouth = up > 0.55 ? .open : .small
        case .play:
            let across = playAcross(at: time)
            let follow = smooth(across) - 0.5
            let hop = bounce(time, period: 2 / 0.9 / 4, hang: 0.25, weight: 0.2)
            moment.fromFeet = true
            moment.offset.width = 4.6 * follow
            moment.offset.height = -1.6 * max(0, hop.height)
            moment.rotation = 5 * follow
            moment.scale = CGSize(width: 1 + hop.squash, height: 1 - hop.squash)
            moment.eyes = .open(look: CGPoint(x: (across - 0.5) * 2.5, y: -1))
            moment.lid = 0
            moment.mouth = .open
        case .sleep:
            let air = breath(time, period: 4.0)
            moment.fromFeet = true
            moment.offset.height = 2.2 - 0.3 * air
            moment.rotation = 8 + 1.2 * sine(time, 8)
            moment.scale = CGSize(width: 1.02 - 0.02 * air, height: 0.98 + 0.03 * air)
            moment.eyes = .closed
            moment.mouth = .small
        case .tired:
            let dip = nod(time, period: 4.2)
            moment.fromFeet = true
            moment.rotation = -6 - 3.5 * dip
            moment.offset.height = 1.6 + 1.0 * dip
            moment.scale = CGSize(width: 1 + 0.02 * dip, height: 1 - 0.03 * dip)
            moment.eyes = dip > 0.8 ? .closed : .half
            moment.mouth = .flat
        case .spent:
            let woozy = dizzy(time, period: 1.5)
            moment.offset.width = 0.85 * woozy.x + 0.8 * woozy.shiver
            moment.offset.height = 0.5 * woozy.y
            moment.rotation = 6 * woozy.y
            moment.eyes = .squeezed
            moment.mouth = .frown
        case .testing:
            let close = peer(time)
            moment.rotation = -3.2 + 5 * close + sine(time, 4.8)
            moment.offset.width = -1.4 + 0.9 * close
            moment.offset.height = -0.8 * bob(time, period: 2.4)
            moment.eyes = close > 0.5 ? .wide(look: CGPoint(x: 1.5, y: -1.2))
                : .open(look: CGPoint(x: 1.35, y: -1.1))
            moment.mouth = .small
        case .longCommand:
            let wait = impatience(time)
            moment.fromFeet = true
            moment.offset.width = -1.4
            moment.offset.height = 0.45 * wait.tap - 2.2 * wait.flip
            moment.rotation = 2.2 * sine(time, 7)
            moment.scale = CGSize(width: 1 + 0.03 * wait.tap - 0.03 * wait.flip,
                                  height: 1 - 0.035 * wait.tap + 0.05 * wait.flip)
            moment.eyes = wait.flip > 0.2 ? .wide(look: CGPoint(x: 1.4, y: -0.6))
                : .open(look: CGPoint(x: 1.2, y: 0.85))
            moment.mouth = wait.flip > 0.2 ? .small : .flat
        case .error:
            let sag = breath(time, period: 2.2)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1.09 + 0.04 * sag, height: 0.85 - 0.04 * sag)
            moment.rotation = 4 * sine(time, 4.5)
            moment.eyes = .cross
            moment.mouth = .frown
            moment.grey = true
        }
        return moment
    }

    /// Where the tossed ball is, 0 at the left hand and 1 at the right.
    static func playAcross(at time: TimeInterval) -> Double {
        let phase = (time * 0.9).truncatingRemainder(dividingBy: 2)
        return phase < 1 ? phase : 2 - phase
    }

    // MARK: - Drawing

    /// How a mark is drawn at the size it is shown.
    ///
    /// **A menu-bar mark is twenty-odd pixels**, and everything finer than a
    /// pixel and a half is mush there: the blush, the eye glints, the soft
    /// flares, the shine, the small orbiting sparkles. So at that size the
    /// mark is a simple one — flat colour, a face of two big eyes and a thick
    /// mouth, a body that fills its box, and cues for work big enough to see.
    struct Style: Equatable {
        /// Flat and bold, for a mark small enough that detail is noise.
        let simple: Bool
        /// The thinnest stroke worth drawing, in the drawing's own units.
        let minStroke: Double

        static func of(size: CGSize) -> Style {
            let extent = min(size.width, size.height)
            return Style(simple: extent <= 34, minStroke: extent <= 34 ? 1.5 / (extent / 64) : 0)
        }

        func stroke(_ width: Double) -> Double { max(width, minStroke) }
    }

    /// Scales a body about the middle of what it occupies so it fills its
    /// box. The designs leave a margin for orbiting sparkles that a small
    /// mark cannot afford.
    private static func fit(_ character: MascotCharacter) -> (scale: Double, centre: CGPoint) {
        switch character {
        case .starBuddy: (1.12, CGPoint(x: 32, y: 32))
        case .cloudGhost: (1.02, CGPoint(x: 32.6, y: 34.7))
        default: (1.04, CGPoint(x: 32, y: 30.5))
        }
    }

    static func draw(_ character: MascotCharacter, pose: MascotPose, time: TimeInterval, colour: Bool,
                     in context: inout GraphicsContext, size: CGSize) {
        let style = Style.of(size: size)
        let moment = moment(for: pose, character: character, at: time, gain: style.simple ? 1.8 : 1)
        let unit = min(size.width, size.height) / 64
        let face = Face.of(character, simple: style.simple)
        let ink = GraphicsContext.Shading.foreground
        // Working leaves room for the cue: the body steps back a little.
        let room = style.simple && pose.isWorking ? 0.95 : 1.0
        let placed = fit(character)
        let fitScale = style.simple ? placed.scale * room : 1
        let fitCentre = style.simple ? placed.centre : CGPoint(x: 32, y: 32)
        // Feet stay where they were: stepping back is stepping back, not up.
        let fitLift = style.simple && pose.isWorking ? (1 - room) * 32 * 0.9 : 0

        if colour, !style.simple, character == .floatBot {
            // The design's ground shadow. It stays put while the arch hovers.
            let lift = max(0, -moment.offset.height)
            let fade = max(0, 0.18 - lift * 0.022)
            if fade > 0.02 {
                var shadow = context
                shadow.scaleBy(x: unit, y: unit)
                shadow.fill(ellipse(32, 58.6, max(6.0, 12 - lift * 0.35), 1.7),
                            with: .color(Color(hex: 0x1D3C8F, opacity: fade)))
            }
        }

        if pose.isWorking, !style.simple {
            drawWork(character, pose: pose, time: time, colour: colour, in: &context, unit: unit, front: false)
        }

        context.drawLayer { layer in
            layer.scaleBy(x: unit, y: unit)
            var body = layer
            body.translateBy(x: 32, y: 32 + fitLift)
            body.scaleBy(x: fitScale, y: fitScale)
            body.translateBy(x: -fitCentre.x, y: -fitCentre.y)
            let pivot = moment.fromFeet ? CGPoint(x: 32, y: face.feet) : fitCentre
            body.translateBy(x: moment.offset.width + pivot.x, y: moment.offset.height + pivot.y)
            body.rotate(by: .degrees(moment.rotation))
            body.scaleBy(x: moment.scale.width, y: moment.scale.height)
            body.translateBy(x: -pivot.x, y: -pivot.y)
            if moment.grey { body.addFilter(.grayscale(1)) }

            if colour {
                drawBody(character, style: style, in: &body)
                if !style.simple { drawShine(character, pose: pose, time: time, in: &body) }
                drawFace(face, moment: moment, colour: true, style: style, in: &body)
            } else {
                // One ink, the face cut out of it, as Clawd's template frames.
                body.fill(outline(character, simple: style.simple), with: ink)
                body.blendMode = .destinationOut
                drawFace(face, moment: moment, colour: false, style: style, in: &body)
                body.blendMode = .normal
            }
        }

        if pose.isWorking {
            if style.simple {
                drawBarWork(character, pose: pose, time: time, colour: colour, in: &context, unit: unit)
            } else {
                drawWork(character, pose: pose, time: time, colour: colour, in: &context, unit: unit, front: true)
            }
        }
        drawAccessory(character, pose: pose, time: time, colour: colour, in: &context, size: size, unit: unit)
    }

    // MARK: Bodies

    /// The Gemini sparkle, its concave sides as quadratics through the points
    /// the logo's own curve passes, in the logo's 64.9-unit box.
    private static let sparkle = Path({ () -> CGPath in
        let path = CGMutablePath()
        let c = 32.45, far = 64.9
        let tips = [CGPoint(x: c, y: 0), CGPoint(x: far, y: c), CGPoint(x: c, y: far), CGPoint(x: 0, y: c)]
        let controls = [CGPoint(x: 40.8, y: 24.1), CGPoint(x: 40.8, y: 40.8),
                        CGPoint(x: 24.1, y: 40.8), CGPoint(x: 24.1, y: 24.1)]
        path.move(to: tips[0])
        for index in 0..<4 {
            path.addQuadCurve(to: tips[(index + 1) % 4], control: controls[index])
        }
        path.closeSubpath()
        // As the design places it: scaled to 0.84 about the middle of the box.
        var place = CGAffineTransform(translationX: 32, y: 32).scaledBy(x: 0.84, y: 0.84)
            .translatedBy(x: -c, y: -c)
        return path.copy(using: &place) ?? path
    }())

    /// The sparkle for a small mark: the same four tips with the sides
    /// pulled out toward a diamond, so the body is plump and the face has
    /// room. The logo's own curve is so concave that at twenty pixels the
    /// star is four needles round a speck.
    private static let sparkleBar = Path({ () -> CGPath in
        let path = CGMutablePath()
        let c = 32.45, far = 64.9, reach = 10.5
        let tips = [CGPoint(x: c, y: 0), CGPoint(x: far, y: c), CGPoint(x: c, y: far), CGPoint(x: 0, y: c)]
        let controls = [CGPoint(x: c + reach, y: c - reach), CGPoint(x: c + reach, y: c + reach),
                        CGPoint(x: c - reach, y: c + reach), CGPoint(x: c - reach, y: c - reach)]
        path.move(to: tips[0])
        for index in 0..<4 { path.addQuadCurve(to: tips[(index + 1) % 4], control: controls[index]) }
        path.closeSubpath()
        var place = CGAffineTransform(translationX: 32, y: 32).scaledBy(x: 0.84, y: 0.84)
            .translatedBy(x: -c, y: -c)
        return path.copy(using: &place) ?? path
    }())

    /// The logo's arch for a small mark. The outer curves are the icon's own
    /// (peak, splayed legs, curled feet). The inner arch sits lower so the
    /// legs stay a solid shape at twenty pixels; `arch` keeps the real hollow.
    private static let archBar = Path({ () -> CGPath in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 54.42, y: 54.85))
        path.addCurve(to: CGPoint(x: 57.88, y: 51.38), control1: CGPoint(x: 57.50, y: 57.16), control2: CGPoint(x: 62.12, y: 55.62))
        path.addCurve(to: CGPoint(x: 32.08, y: 5.17), control1: CGPoint(x: 45.18, y: 39.06), control2: CGPoint(x: 47.87, y: 5.17))
        path.addCurve(to: CGPoint(x: 6.29, y: 51.38), control1: CGPoint(x: 16.30, y: 5.17), control2: CGPoint(x: 18.99, y: 39.06))
        path.addCurve(to: CGPoint(x: 9.75, y: 54.85), control1: CGPoint(x: 1.66, y: 56.00), control2: CGPoint(x: 6.67, y: 57.16))
        path.addCurve(to: CGPoint(x: 32.08, y: 48), control1: CGPoint(x: 18.2, y: 51.4), control2: CGPoint(x: 22.4, y: 48))
        path.addCurve(to: CGPoint(x: 54.42, y: 54.85), control1: CGPoint(x: 41.76, y: 48), control2: CGPoint(x: 45.9, y: 51.4))
        path.closeSubpath()
        return path
    }())

    /// Antigravity's arch, the official icon path scaled into this box.
    /// Feet sit on y = 56; the width matches the mark it replaces.
    private static let arch = Path({ () -> CGPath in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 54.42, y: 54.85))
        path.addCurve(to: CGPoint(x: 57.88, y: 51.38), control1: CGPoint(x: 57.50, y: 57.16), control2: CGPoint(x: 62.12, y: 55.62))
        path.addCurve(to: CGPoint(x: 32.08, y: 5.17), control1: CGPoint(x: 45.18, y: 39.06), control2: CGPoint(x: 47.87, y: 5.17))
        path.addCurve(to: CGPoint(x: 6.29, y: 51.38), control1: CGPoint(x: 16.30, y: 5.17), control2: CGPoint(x: 18.99, y: 39.06))
        path.addCurve(to: CGPoint(x: 9.75, y: 54.85), control1: CGPoint(x: 1.66, y: 56.00), control2: CGPoint(x: 6.67, y: 57.16))
        path.addCurve(to: CGPoint(x: 32.08, y: 32.51), control1: CGPoint(x: 21.69, y: 46.76), control2: CGPoint(x: 20.92, y: 32.51))
        path.addCurve(to: CGPoint(x: 54.42, y: 54.85), control1: CGPoint(x: 43.25, y: 32.51), control2: CGPoint(x: 42.48, y: 46.76))
        path.closeSubpath()
        return path
    }())

    /// The Codex cloud, traced from the logo's own outline (the overlapping
    /// lobes, not a ghost hem) and scaled into the same box the old cloud
    /// occupied, so the mark stays the same size. The border is white.
    private static let cloud = Path({ () -> CGPath in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 24.66, y: 12.38))
        path.addCurve(to: CGPoint(x: 30.57, y: 11.61), control1: CGPoint(x: 26.53, y: 11.62), control2: CGPoint(x: 28.57, y: 11.36))
        path.addCurve(to: CGPoint(x: 37.54, y: 14.94), control1: CGPoint(x: 33.20, y: 11.91), control2: CGPoint(x: 35.66, y: 13.08))
        path.addLine(to: CGPoint(x: 37.67, y: 14.94))
        path.addCurve(to: CGPoint(x: 45.55, y: 15.63), control1: CGPoint(x: 40.30, y: 14.26), control2: CGPoint(x: 43.08, y: 14.51))
        path.addLine(to: CGPoint(x: 45.68, y: 15.71))
        path.addLine(to: CGPoint(x: 45.96, y: 15.84))
        path.addCurve(to: CGPoint(x: 51.62, y: 22.04), control1: CGPoint(x: 48.54, y: 17.15), control2: CGPoint(x: 50.55, y: 19.35))
        path.addQuadCurve(to: CGPoint(x: 52.42, y: 26.17), control: CGPoint(x: 52.39, y: 24.00))
        path.addCurve(to: CGPoint(x: 52.08, y: 29.32), control1: CGPoint(x: 52.47, y: 27.23), control2: CGPoint(x: 52.35, y: 28.29))
        path.addCurve(to: CGPoint(x: 52.16, y: 29.60), control1: CGPoint(x: 52.05, y: 29.42), control2: CGPoint(x: 52.08, y: 29.54))
        path.addQuadCurve(to: CGPoint(x: 55.21, y: 35.21), control: CGPoint(x: 54.48, y: 31.95))
        path.addQuadCurve(to: CGPoint(x: 52.93, y: 45.18), control: CGPoint(x: 56.37, y: 40.73))
        path.addLine(to: CGPoint(x: 52.57, y: 45.59))
        path.addCurve(to: CGPoint(x: 46.89, y: 49.20), control1: CGPoint(x: 51.07, y: 47.32), control2: CGPoint(x: 49.09, y: 48.57))
        path.addCurve(to: CGPoint(x: 46.68, y: 49.39), control1: CGPoint(x: 46.79, y: 49.22), control2: CGPoint(x: 46.71, y: 49.29))
        path.addCurve(to: CGPoint(x: 35.19, y: 57.98), control1: CGPoint(x: 45.27, y: 54.52), control2: CGPoint(x: 40.52, y: 58.07))
        path.addCurve(to: CGPoint(x: 27.03, y: 54.63), control1: CGPoint(x: 32.14, y: 57.98), control2: CGPoint(x: 29.21, y: 56.77))
        path.addCurve(to: CGPoint(x: 26.78, y: 54.55), control1: CGPoint(x: 26.97, y: 54.55), control2: CGPoint(x: 26.87, y: 54.52))
        path.addCurve(to: CGPoint(x: 23.68, y: 54.91), control1: CGPoint(x: 25.77, y: 54.83), control2: CGPoint(x: 24.72, y: 54.95))
        path.addCurve(to: CGPoint(x: 18.64, y: 53.72), control1: CGPoint(x: 21.93, y: 54.91), control2: CGPoint(x: 20.21, y: 54.50))
        path.addCurve(to: CGPoint(x: 14.48, y: 50.24), control1: CGPoint(x: 17.00, y: 52.91), control2: CGPoint(x: 15.57, y: 51.71))
        path.addQuadCurve(to: CGPoint(x: 13.40, y: 48.64), control: CGPoint(x: 13.86, y: 49.46))
        path.addCurve(to: CGPoint(x: 12.44, y: 46.16), control1: CGPoint(x: 13.01, y: 47.84), control2: CGPoint(x: 12.69, y: 47.01))
        path.addCurve(to: CGPoint(x: 12.42, y: 40.22), control1: CGPoint(x: 11.93, y: 44.21), control2: CGPoint(x: 11.92, y: 42.17))
        path.addLine(to: CGPoint(x: 12.42, y: 40.09))
        path.addLine(to: CGPoint(x: 12.37, y: 39.96))
        path.addCurve(to: CGPoint(x: 9.68, y: 35.70), control1: CGPoint(x: 11.17, y: 38.75), control2: CGPoint(x: 10.25, y: 37.30))
        path.addCurve(to: CGPoint(x: 9.04, y: 32.60), control1: CGPoint(x: 9.31, y: 34.71), control2: CGPoint(x: 9.09, y: 33.66))
        path.addCurve(to: CGPoint(x: 9.40, y: 28.47), control1: CGPoint(x: 8.93, y: 31.21), control2: CGPoint(x: 9.05, y: 29.82))
        path.addCurve(to: CGPoint(x: 17.61, y: 20.28), control1: CGPoint(x: 10.57, y: 24.53), control2: CGPoint(x: 13.66, y: 21.44))
        path.addCurve(to: CGPoint(x: 17.79, y: 20.13), control1: CGPoint(x: 17.69, y: 20.26), control2: CGPoint(x: 17.76, y: 20.21))
        path.addCurve(to: CGPoint(x: 19.93, y: 15.94), control1: CGPoint(x: 18.24, y: 18.61), control2: CGPoint(x: 18.97, y: 17.20))
        path.addCurve(to: CGPoint(x: 24.66, y: 12.36), control1: CGPoint(x: 21.17, y: 14.36), control2: CGPoint(x: 22.80, y: 13.12))
        path.closeSubpath()
        return path
    }())

    /// The logo's `>` and `_`, in the same box as `cloud`.
    private static let codexChevron = Path({ () -> CGPath in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 23.11, y: 27.59))
        path.addCurve(to: CGPoint(x: 20.98, y: 27.17), control1: CGPoint(x: 22.61, y: 26.94), control2: CGPoint(x: 21.69, y: 26.76))
        path.addCurve(to: CGPoint(x: 20.27, y: 29.22), control1: CGPoint(x: 20.27, y: 27.58), control2: CGPoint(x: 19.96, y: 28.46))
        path.addLine(to: CGPoint(x: 23.55, y: 34.98))
        path.addLine(to: CGPoint(x: 20.27, y: 40.48))
        path.addCurve(to: CGPoint(x: 20.18, y: 42.18), control1: CGPoint(x: 19.92, y: 40.98), control2: CGPoint(x: 19.89, y: 41.64))
        path.addCurve(to: CGPoint(x: 21.65, y: 43.05), control1: CGPoint(x: 20.47, y: 42.72), control2: CGPoint(x: 21.04, y: 43.06))
        path.addCurve(to: CGPoint(x: 23.11, y: 42.15), control1: CGPoint(x: 22.27, y: 43.05), control2: CGPoint(x: 22.83, y: 42.70))
        path.addLine(to: CGPoint(x: 26.85, y: 35.83))
        path.addCurve(to: CGPoint(x: 26.85, y: 34.18), control1: CGPoint(x: 27.17, y: 35.32), control2: CGPoint(x: 27.17, y: 34.68))
        path.closeSubpath()
        return path
    }())

    private static let codexDash = Path({ () -> CGPath in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 33.67, y: 39.65))
        path.addCurve(to: CGPoint(x: 32.22, y: 41.29), control1: CGPoint(x: 32.85, y: 39.75), control2: CGPoint(x: 32.22, y: 40.46))
        path.addCurve(to: CGPoint(x: 33.67, y: 42.93), control1: CGPoint(x: 32.22, y: 42.12), control2: CGPoint(x: 32.85, y: 42.83))
        path.addLine(to: CGPoint(x: 43.04, y: 42.93))
        path.addCurve(to: CGPoint(x: 44.65, y: 42.17), control1: CGPoint(x: 43.68, y: 43.01), control2: CGPoint(x: 44.30, y: 42.71))
        path.addCurve(to: CGPoint(x: 44.65, y: 40.40), control1: CGPoint(x: 44.99, y: 41.64), control2: CGPoint(x: 44.99, y: 40.94))
        path.addCurve(to: CGPoint(x: 43.04, y: 39.65), control1: CGPoint(x: 44.30, y: 39.86), control2: CGPoint(x: 43.68, y: 39.57))
        path.closeSubpath()
        return path
    }())

    static func outline(_ character: MascotCharacter, simple: Bool = false) -> Path {
        switch character {
        case .starBuddy: simple ? sparkleBar : sparkle
        case .cloudGhost: cloud
        default: simple ? archBar : arch
        }
    }

    private static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    /// A soft brand flare: the colour solid to `solid` of the way out, then
    /// fading, as the logo's radial gradients do.
    private static func flare(_ hex: UInt32, solid: Double) -> Gradient {
        Gradient(stops: [.init(color: Color(hex: hex), location: 0),
                         .init(color: Color(hex: hex), location: solid),
                         .init(color: Color(hex: hex, opacity: 0), location: 1)])
    }

    /// The icon's cap, traced from the rendered logo: yellow on the upper
    /// left, red down the right shoulder, a green wedge on the left, and the
    /// light-blue sheen along the right leg. The caller has clipped to the arch.
    private static func fillAntigravityColours(in context: inout GraphicsContext, shine: Bool) {
        func blob(_ hex: UInt32, _ points: [CGPoint]) {
            var path = Path()
            guard let first = points.first else { return }
            path.move(to: first)
            path.addLines(Array(points.dropFirst()))
            path.closeSubpath()
            context.fill(path, with: .color(Color(hex: hex)))
        }
        blob(0xFBBC04, [CGPoint(x: 21.38, y: 13.25), CGPoint(x: 26.62, y: 15.25), CGPoint(x: 30.25, y: 15.88),
                        CGPoint(x: 36.75, y: 15.50), CGPoint(x: 33.25, y: 10.88), CGPoint(x: 30.75, y: 4.88),
                        CGPoint(x: 28.12, y: 5.50), CGPoint(x: 25.75, y: 7.00), CGPoint(x: 22.88, y: 10.25)])
        blob(0xFC413D, [CGPoint(x: 30.88, y: 4.88), CGPoint(x: 33.25, y: 10.50), CGPoint(x: 39.00, y: 17.75),
                        CGPoint(x: 46.50, y: 24.00), CGPoint(x: 44.62, y: 17.62), CGPoint(x: 40.62, y: 9.62),
                        CGPoint(x: 35.88, y: 5.50)])
        blob(0x00B95C, [CGPoint(x: 27.00, y: 15.38), CGPoint(x: 21.38, y: 13.38), CGPoint(x: 19.62, y: 17.12),
                        CGPoint(x: 17.50, y: 24.62), CGPoint(x: 21.50, y: 21.38), CGPoint(x: 27.00, y: 19.00)])
        blob(0x749BFF, [CGPoint(x: 43.38, y: 21.88), CGPoint(x: 42.88, y: 25.50), CGPoint(x: 43.75, y: 28.62),
                        CGPoint(x: 46.50, y: 33.50), CGPoint(x: 50.50, y: 37.75), CGPoint(x: 46.50, y: 24.12)])
        guard shine else { return }
        var highlight = context
        highlight.translateBy(x: 29.2, y: 8.6)
        highlight.rotate(by: .degrees(-26))
        highlight.fill(ellipse(0, 0, 2.3, 1.1), with: .color(.white.opacity(0.30)))
    }

    private static func drawBody(_ character: MascotCharacter, style: Style, in context: inout GraphicsContext) {
        if style.simple { drawFlatBody(character, in: &context); return }
        switch character {
        case .starBuddy:
            let shape = sparkle
            context.fill(shape, with: .linearGradient(
                Gradient(stops: [.init(color: Color(hex: 0x4893FC), location: 0.27),
                                 .init(color: Color(hex: 0x969DFF), location: 0.777),
                                 .init(color: Color(hex: 0xBD99FE), location: 1)]),
                startPoint: CGPoint(x: 17.5, y: 44), endPoint: CGPoint(x: 46, y: 20)))
            var inside = context
            inside.clip(to: shape)
            func radial(_ path: Path, _ gradient: Gradient, centre: CGPoint, radius: Double, angle: Double = 0) {
                var layer = inside
                layer.translateBy(x: centre.x, y: centre.y)
                layer.rotate(by: .degrees(angle))
                layer.translateBy(x: -centre.x, y: -centre.y)
                layer.fill(path, with: .radialGradient(gradient, center: centre, startRadius: 0, endRadius: radius))
            }
            radial(ellipse(38.0, 36.0, 27.7, 23.5), flare(0x3186FF, solid: 0.65), centre: CGPoint(x: 38.0, y: 36.0), radius: 27.7)
            radial(ellipse(40.5, 17.5, 7.6, 6.6), flare(0x749BFF, solid: 0.5), centre: CGPoint(x: 40.5, y: 17.5), radius: 7.6)
            radial(ellipse(25.0, 7.0, 10, 12), flare(0xFC413D, solid: 0.72), centre: CGPoint(x: 25.0, y: 7.0), radius: 12, angle: -30)
            radial(ellipse(9.0, 31.0, 11.5, 7.6), flare(0xFBBC04, solid: 0.8), centre: CGPoint(x: 9.0, y: 31.0), radius: 11.5)
            radial(ellipse(25.0, 54.0, 12, 10), flare(0x00B95C, solid: 0.75), centre: CGPoint(x: 25.0, y: 54.0), radius: 12, angle: 25)
            var shine = context
            shine.translateBy(x: 29.6, y: 14.5)
            shine.rotate(by: .degrees(-12))
            shine.fill(ellipse(0, 0, 1.2, 3.4), with: .color(.white.opacity(0.35)))

        case .floatBot:
            let shape = arch
            context.fill(shape, with: .color(Color(hex: 0x3186FF)))
            var inside = context
            inside.clip(to: shape)
            fillAntigravityColours(in: &inside, shine: true)

        default:
            let shape = cloud
            context.stroke(shape, with: .color(.white),
                           style: StrokeStyle(lineWidth: 4.6, lineJoin: .round))
            context.fill(shape, with: .color(Color(hex: 0x262394)))
            context.fill(shape, with: .linearGradient(
                Gradient(stops: [.init(color: Color(hex: 0xB1A7FF), location: 0),
                                 .init(color: Color(hex: 0x7A9DFF), location: 0.5),
                                 .init(color: Color(hex: 0x3941FF), location: 1)]),
                startPoint: CGPoint(x: 32, y: 11.5), endPoint: CGPoint(x: 32, y: 58)))
        }
    }

    /// The bar-size body: flat colour, hard edges, no gradient to blur and no
    /// shine to speck. The brand's colours stay, as blocks.
    private static func drawFlatBody(_ character: MascotCharacter, in context: inout GraphicsContext) {
        switch character {
        case .starBuddy:
            let shape = sparkleBar
            context.fill(shape, with: .color(Color(hex: 0x3186FF)))
            var tips = context
            tips.clip(to: shape)
            // The three flares, as the logo's tips: red above, yellow to the
            // left, green below — each big enough to be a colour, not a speck.
            tips.fill(Path(CGRect(x: 0, y: 0, width: 64, height: 17.5)), with: .color(Color(hex: 0xFC413D)))
            tips.fill(Path(CGRect(x: 0, y: 0, width: 17.5, height: 64)), with: .color(Color(hex: 0xFBBC04)))
            tips.fill(Path(CGRect(x: 0, y: 46.5, width: 64, height: 20)), with: .color(Color(hex: 0x00B95C)))

        case .floatBot:
            let shape = archBar
            context.fill(shape, with: .color(Color(hex: 0x3186FF)))
            var inside = context
            inside.clip(to: shape)
            fillAntigravityColours(in: &inside, shine: false)

        default:
            let shape = cloud
            context.stroke(shape, with: .color(.white), style: StrokeStyle(lineWidth: 5.6, lineJoin: .round))
            context.fill(shape, with: .color(Color(hex: 0x262394)))
            context.fill(shape, with: .linearGradient(
                Gradient(colors: [Color(hex: 0xA9A4FF), Color(hex: 0x5C7BFF)]),
                startPoint: CGPoint(x: 32, y: 11.5), endPoint: CGPoint(x: 32, y: 58)))
        }
    }

    /// A glint of light sweeping across Antigravity's marks every few
    /// seconds, and on the arch a twinkle at the peak just after it. Panel
    /// size only: at bar size it is a speck. Drawn in the body's own
    /// coordinates, so it rides along with every hop and tilt.
    private static func drawShine(_ character: MascotCharacter, pose: MascotPose, time: TimeInterval,
                                  in context: inout GraphicsContext) {
        guard character != .cloudGhost else { return }
        switch pose {
        case .sleep, .tired, .spent, .error: return
        default: break
        }
        let period = pose.isWorking || pose == .celebrate ? 3.2 : 4.4
        let t = wrap(time, period)
        let shape = outline(character)
        if t < 0.2 {
            // Off to the left at the start and off to the right at the end.
            let x = -12 + 88 * smooth(t / 0.2)
            var band = context
            band.clip(to: shape)
            band.translateBy(x: x, y: 32)
            band.rotate(by: .degrees(24))
            band.fill(Path(CGRect(x: -5, y: -40, width: 10, height: 80)), with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.42), .white.opacity(0)]),
                startPoint: CGPoint(x: -5, y: 0), endPoint: CGPoint(x: 5, y: 0)))
        }
        guard character == .floatBot else { return }
        let twinkle = hold(t, 0.12, 0.17, 0.2, 0.3)
        if twinkle > 0.02 {
            drawSpark(in: &context, at: CGPoint(x: 37.5, y: 7.5), radius: 3.6 * twinkle,
                      colour: .white.opacity(0.95 * twinkle))
        }
    }

    // MARK: Faces

    struct Face {
        var left: CGPoint
        var right: CGPoint
        var blushY: Double
        var blushX: (Double, Double)
        var mouthY: Double
        var feet: Double
        var ink: Color
        var blush: Color
        /// Codex's face is the logo's `>_`, punched through the cloud.
        var promptMark = false
        /// White round the pupils, so two eyes read as two at bar size.
        var sclera = false

        static func of(_ character: MascotCharacter, simple: Bool = false) -> Face {
            switch character {
            case .floatBot where simple:
                // Lower and wider than the design's: at twenty pixels its eyes
                // sit on the cap's colours and run together into one smudge.
                // Here they are on plain blue, apart, each with its white.
                Face(left: CGPoint(x: 25.4, y: 27.8), right: CGPoint(x: 38.6, y: 27.8), blushY: 31.6,
                     blushX: (21.6, 42.4), mouthY: 35.2, feet: 56, ink: Color(hex: 0x231F4A), blush: Color(hex: 0xFF9FB8),
                     promptMark: false, sclera: true)
            case .starBuddy:
                Face(left: CGPoint(x: 25.5, y: 31), right: CGPoint(x: 38.5, y: 31), blushY: 36.2,
                     blushX: (20.8, 43.2), mouthY: 38.6, feet: 59, ink: Color(hex: 0x231F4A), blush: Color(hex: 0xFF9FB8),
                     promptMark: false)
            case .cloudGhost:
                Face(left: CGPoint(x: 24, y: 38), right: CGPoint(x: 40, y: 38), blushY: 43.2,
                     blushX: (19.4, 44.6), mouthY: 45, feet: 56, ink: Color(hex: 0x1A1866), blush: Color(hex: 0xFF9FD6),
                     promptMark: true)
            default:
                // On the blue chest, under the cap and above the hollow.
                Face(left: CGPoint(x: 26.2, y: 21.2), right: CGPoint(x: 37.8, y: 21.2), blushY: 25.2,
                     blushX: (22.8, 41.2), mouthY: 27.4, feet: 56, ink: Color(hex: 0x231F4A), blush: Color(hex: 0xFF9FB8),
                     promptMark: false)
            }
        }
    }

    /// Codex's `>_`, a hole in the cloud the way the logo draws it. `offset`
    /// is the pose's glance, so a look still moves the mark. In one-ink mode
    /// the caller has already set `.destinationOut`.
    /// `lid` is a blink: the `>` folds flat about its middle and opens again,
    /// while the cursor keeps its own time.
    /// At bar size the colour mark paints it in navy instead: a hole shows
    /// whatever the menu bar is behind it, and on a tinted bar that is a
    /// blue-green face lost in the purple.
    private static func drawLogoPrompt(cursor: Bool, offset: CGPoint, lid: Double, colour: Bool, solid: Bool = false,
                                       in context: inout GraphicsContext) {
        var layer = context
        layer.translateBy(x: offset.x, y: offset.y)
        if colour, !solid { layer.blendMode = .destinationOut }
        let ink = GraphicsContext.Shading.color(colour && solid ? Color(hex: 0x0E0B30) : .black)
        if lid > 0.01 {
            var chevron = layer
            let middle = 35.1
            chevron.translateBy(x: 0, y: middle)
            chevron.scaleBy(x: 1 + 0.08 * lid, y: max(0.14, 1 - lid))
            chevron.translateBy(x: 0, y: -middle)
            chevron.fill(codexChevron, with: ink)
        } else {
            layer.fill(codexChevron, with: ink)
        }
        if cursor { layer.fill(codexDash, with: ink) }
    }

    /// The face for a moment. In one-ink mode it is drawn with
    /// `.destinationOut` already set, so everything here cuts the body.
    private static func drawFace(_ face: Face, moment: Moment, colour: Bool, style: Style,
                                 in context: inout GraphicsContext) {
        // Darker still at bar size: navy on the blue body is the contrast the
        // whole face rests on.
        let ink = GraphicsContext.Shading.color(colour ? (style.simple ? Color(hex: 0x0E0B30) : face.ink) : .black)
        let line = StrokeStyle(lineWidth: style.stroke(style.simple ? 3 : 2), lineCap: .round, lineJoin: .round)
        // Bigger features at bar size: two wide eyes and a thick mouth are
        // what survive twenty pixels.
        let grow = style.simple ? 1.3 : 1.0

        if colour, !style.simple, !face.promptMark, moment.eyes != .cross {
            for x in [face.blushX.0, face.blushX.1] {
                context.fill(ellipse(x, face.blushY, 2.6, 1.7), with: .color(face.blush.opacity(0.8)))
            }
        }

        for (index, eye) in [face.left, face.right].enumerated() {
            switch moment.eyes {
            case .open(let look), .wide(let look):
                if face.promptMark {
                    guard index == 0 else { continue }
                    drawLogoPrompt(cursor: true, offset: look, lid: moment.lid, colour: colour,
                                   solid: style.simple, in: &context)
                    continue
                }
                let wide = { if case .wide = moment.eyes { return true } else { return false } }()
                let centre = CGPoint(x: eye.x + look.x, y: eye.y + look.y)
                if moment.lid > 0.85 {
                    // Shut for the middle of a blink: the same lid line as asleep.
                    var arc = Path()
                    arc.move(to: CGPoint(x: centre.x - 3, y: centre.y - 0.6))
                    arc.addQuadCurve(to: CGPoint(x: centre.x + 3, y: centre.y - 0.6),
                                     control: CGPoint(x: centre.x, y: centre.y + 2.4))
                    context.stroke(arc, with: ink, style: line)
                    continue
                }
                // Closing and opening: the eye squashes toward its lower lid.
                let open = 1 - 0.8 * moment.lid
                if face.sclera, colour {
                    // The white stays put; the pupil does the looking.
                    let white = (wide ? 5.6 : 5.2) * open
                    context.fill(ellipse(eye.x, eye.y + 5.2 * (1 - open) * 0.5, wide ? 4.9 : 4.6, max(1.2, white)),
                                 with: .color(.white))
                    let pupil = CGPoint(x: eye.x + 0.7 * look.x, y: eye.y + 0.7 * look.y)
                    context.fill(ellipse(pupil.x, pupil.y + 3.4 * (1 - open) * 0.5, wide ? 3.0 : 2.8,
                                         max(0.9, 3.4 * open)), with: ink)
                    continue
                }
                let height = (wide ? 4.4 : 4) * grow
                context.fill(ellipse(centre.x, centre.y + height * (1 - open) * 0.5,
                                     (wide ? 3.3 : 3) * grow, max(0.9, height * open)), with: ink)
                if colour, !style.simple, moment.lid < 0.3 {
                    context.fill(ellipse(centre.x + 1, centre.y - 1.5, 1.1, 1.1), with: .color(.white))
                }
            case .closed:
                var arc = Path()
                arc.move(to: CGPoint(x: eye.x - 3, y: eye.y - 1))
                arc.addQuadCurve(to: CGPoint(x: eye.x + 3, y: eye.y - 1), control: CGPoint(x: eye.x, y: eye.y + 3.2))
                context.stroke(arc, with: ink, style: line)
            case .half:
                context.fill(Path(roundedRect: CGRect(x: eye.x - 3, y: eye.y - 0.6, width: 6, height: 3.6), cornerRadius: 1.8), with: ink)
                var brow = Path()
                brow.move(to: CGPoint(x: eye.x - 3.2, y: eye.y - 1.4))
                brow.addLine(to: CGPoint(x: eye.x + 3.2, y: eye.y - 1.4))
                context.stroke(brow, with: ink, style: StrokeStyle(lineWidth: style.stroke(1.2), lineCap: .round))
            case .happy:
                var arc = Path()
                arc.move(to: CGPoint(x: eye.x - 3, y: eye.y + 1.2))
                arc.addQuadCurve(to: CGPoint(x: eye.x + 3, y: eye.y + 1.2), control: CGPoint(x: eye.x, y: eye.y - 3.4))
                context.stroke(arc, with: ink, style: line)
            case .cross:
                var cross = Path()
                cross.move(to: CGPoint(x: eye.x - 2.6, y: eye.y - 2.6)); cross.addLine(to: CGPoint(x: eye.x + 2.6, y: eye.y + 2.6))
                cross.move(to: CGPoint(x: eye.x + 2.6, y: eye.y - 2.6)); cross.addLine(to: CGPoint(x: eye.x - 2.6, y: eye.y + 2.6))
                context.stroke(cross, with: ink, style: StrokeStyle(lineWidth: style.stroke(2.2), lineCap: .round))
            case .squeezed:
                // > <
                let side: Double = index == 0 ? 1 : -1
                var chevron = Path()
                chevron.move(to: CGPoint(x: eye.x - 2.4 * side, y: eye.y - 2.6))
                chevron.addLine(to: CGPoint(x: eye.x + 2.4 * side, y: eye.y))
                chevron.addLine(to: CGPoint(x: eye.x - 2.4 * side, y: eye.y + 2.6))
                context.stroke(chevron, with: ink, style: line)
            case .prompt(let cursor, let look):
                // The logo's `>_`, the cursor (the dash) blinking.
                guard index == 0 else { continue }
                drawLogoPrompt(cursor: cursor, offset: look, lid: moment.lid, colour: colour,
                                   solid: style.simple, in: &context)
            }
        }
        if face.promptMark {
            switch moment.eyes {
            case .open, .wide, .prompt: return
            default: break
            }
        }
        if case .prompt = moment.eyes { return }

        let y = face.mouthY
        var mouth = Path()
        switch moment.mouth {
        case .smile:
            mouth.move(to: CGPoint(x: 29.6, y: y - 0.6))
            mouth.addQuadCurve(to: CGPoint(x: 34.4, y: y - 0.6), control: CGPoint(x: 32, y: y + 2.2))
            context.stroke(mouth, with: ink, style: StrokeStyle(lineWidth: style.stroke(style.simple ? 2.6 : 1.8), lineCap: .round))
        case .flat:
            mouth.move(to: CGPoint(x: 30.2, y: y))
            mouth.addLine(to: CGPoint(x: 33.8, y: y))
            context.stroke(mouth, with: ink, style: StrokeStyle(lineWidth: style.stroke(style.simple ? 2.6 : 1.8), lineCap: .round))
        case .small:
            context.fill(ellipse(32, y + 0.4, 1.4 * grow, 1.7 * grow), with: ink)
        case .open:
            mouth.move(to: CGPoint(x: 29.4, y: y - 0.8))
            mouth.addQuadCurve(to: CGPoint(x: 34.6, y: y - 0.8), control: CGPoint(x: 32, y: y + 4.2))
            mouth.closeSubpath()
            context.fill(mouth, with: ink)
        case .frown:
            mouth.move(to: CGPoint(x: 29.6, y: y + 1.2))
            mouth.addQuadCurve(to: CGPoint(x: 34.4, y: y + 1.2), control: CGPoint(x: 32, y: y - 1.6))
            context.stroke(mouth, with: ink, style: StrokeStyle(lineWidth: style.stroke(style.simple ? 2.6 : 1.8), lineCap: .round))
        }
    }

    // MARK: Effects

    /// What each character does at work, from its design: Star Buddy's three
    /// sparkles orbit and twinkle, Float Bot types chevrons and drops thrust
    /// from under its arch, Cloud Ghost's data bits rise up its sides.
    private static func drawWork(_ character: MascotCharacter, pose: MascotPose, time: TimeInterval, colour: Bool,
                                 in context: inout GraphicsContext, unit: CGFloat, front: Bool) {
        let speed = pose == .run ? 1.8 : 1.0
        func tone(_ hex: UInt32, _ opacity: Double = 1) -> Color {
            colour ? Color(hex: hex, opacity: opacity) : Color.primary.opacity(opacity)
        }
        var layer = context
        layer.scaleBy(x: unit, y: unit)
        switch character {
        case .starBuddy:
            for (index, hex) in [UInt32(0xFC413D), 0xFBBC04, 0x00B95C].enumerated() {
                let angle = time * 1.6 * speed + Double(index) * 2 * .pi / 3
                // In front on the lower half of the orbit, behind on the upper.
                guard (sin(angle) > 0) == front else { continue }
                let centre = CGPoint(x: 32 + 27 * cos(angle), y: 32 + 13 * sin(angle))
                let twinkle = 0.45 * sin(time * 7.5 + Double(index) * 2.1)
                let radius = max(1.15, 2.4 + 1.1 * sin(angle) + twinkle)
                drawSpark(in: &layer, at: centre, radius: radius, colour: tone(hex, 0.55 + 0.4 * max(0, sin(angle))))
            }
        case .floatBot:
            guard front else {
                // Burst out of the hollow, then linger. The run locks this to
                // the same period as the hop, so the thrust is the hop.
                let period = pose == .run ? 0.48 : 0.90
                let hues: [UInt32] = [0xFC413D, 0xFBBC04, 0x00B95C]
                for index in 0..<3 {
                    let fall = easeOutCubic(wrap(time + Double(index) * period / 3, period))
                    let centre = CGPoint(x: 32 + 4.2 * sin(Double(index) * 2.1 + time * 3),
                                         y: 36 + 18 * fall)
                    drawSpark(in: &layer, at: centre, radius: 2.6 * (1 - fall * 0.5),
                              colour: tone(hues[index], 1 - fall * 0.82))
                }
                return
            }
            let period = pose == .run ? 0.36 : 0.55
            for (index, side) in [-1.0, 1.0].enumerated() {
                let local = wrap(time + Double(index) * period * 0.5, period)
                let pulse = local < 0.42 ? easeOutCubic(local / 0.42) : 1 - smooth((local - 0.42) / 0.58)
                let x = 32 + side * (23.2 + 3.4 * pulse)
                var chevron = Path()
                chevron.move(to: CGPoint(x: x, y: 24.2))
                chevron.addLine(to: CGPoint(x: x + side * 3.6, y: 27.8))
                chevron.addLine(to: CGPoint(x: x, y: 31.4))
                layer.stroke(chevron, with: .color(tone(0x4893FC, 0.28 + 0.72 * pulse)),
                             style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                // The keystroke travelling out past the one that just landed.
                let ghostX = x + side * (2.4 + 2.2 * pulse)
                var ghost = Path()
                ghost.move(to: CGPoint(x: ghostX, y: 25.4))
                ghost.addLine(to: CGPoint(x: ghostX + side * 2.6, y: 28))
                ghost.addLine(to: CGPoint(x: ghostX, y: 30.6))
                layer.stroke(ghost, with: .color(tone(0x4893FC, 0.45 * pulse)),
                             style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        default:
            guard !front else { return }
            let period = pose == .run ? 0.72 : 1.15
            let hues: [UInt32] = [0xB1A7FF, 0x7A9DFF, 0x3941FF]
            for index in 0..<5 {
                let rise = easeOutCubic(wrap(time + Double(index) * period / 5, period))
                let lane = index % 2
                let stagger = Double(index % 3) * 2.1
                let x = lane == 0 ? 1.2 + stagger : 60.2 - stagger
                let y = 52 - 36 * rise
                let side = 2.3 + 0.45 * Double(lane)
                layer.fill(Path(roundedRect: CGRect(x: x, y: y, width: side, height: side), cornerRadius: 0.8),
                           with: .color(tone(hues[index % 3], 0.4 + 0.6 * (1 - rise))))
            }
        }
    }

    /// Work at bar size: the body has stepped back to leave room, and each
    /// character's cue from its design is drawn once, big and bold, in that
    /// room — two sparkles round the star, chevrons at either side of the arch,
    /// bits rising either side of the cloud.
    private static func drawBarWork(_ character: MascotCharacter, pose: MascotPose, time: TimeInterval, colour: Bool,
                                    in context: inout GraphicsContext, unit: CGFloat) {
        let speed = pose == .run ? 1.8 : 1.0
        func tone(_ hex: UInt32, _ opacity: Double = 1) -> Color {
            colour ? Color(hex: hex, opacity: opacity) : Color.primary.opacity(opacity)
        }
        var layer = context
        layer.scaleBy(x: unit, y: unit)
        switch character {
        case .starBuddy:
            let hues: [UInt32] = [0xFC413D, 0xFBBC04, 0x00B95C]
            for index in 0..<2 {
                let angle = time * 3.2 * speed + Double(index) * .pi
                let hue = hues[(Int(time * 0.8 * speed) + index) % hues.count]
                let twinkle = 1.3 * sin(time * 7.5 + Double(index) * 1.7)
                let centre = CGPoint(x: 32 + 23 * cos(angle), y: 33 + 20 * sin(angle))
                drawSpark(in: &layer, at: centre, radius: max(5.2, 6.6 + twinkle), colour: tone(hue))
            }
        case .floatBot:
            let period = pose == .run ? 0.48 : 0.90
            let hues: [UInt32] = [0xFC413D, 0xFBBC04, 0x00B95C]
            for index in 0..<2 {
                let fall = easeOutCubic(wrap(time + Double(index) * period / 2, period))
                let centre = CGPoint(x: 32 + (index == 0 ? -5.0 : 5.0), y: 52 + 8 * fall)
                drawSpark(in: &layer, at: centre, radius: 5.2 * (1 - 0.28 * fall),
                          colour: tone(hues[index], 0.95 - 0.7 * fall))
            }
            let typePeriod = pose == .run ? 0.36 : 0.50
            for (index, side) in [-1.0, 1.0].enumerated() {
                let local = wrap(time + Double(index) * typePeriod * 0.5, typePeriod)
                let pulse = local < 0.42 ? easeOutCubic(local / 0.42) : 1 - smooth((local - 0.42) / 0.58)
                let x = 32 + side * (26.4 + 4.2 * pulse)
                var chevron = Path()
                chevron.move(to: CGPoint(x: x - side * 2.5, y: 22))
                chevron.addLine(to: CGPoint(x: x + side * 2.2, y: 29))
                chevron.addLine(to: CGPoint(x: x - side * 2.5, y: 36))
                layer.stroke(chevron, with: .color(tone(0x4893FC, 0.4 + 0.6 * pulse)),
                             style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        default:
            let period = pose == .run ? 0.70 : 1.05
            let hues: [UInt32] = [0xB1A7FF, 0x7A9DFF, 0x3941FF]
            let lanes = [0.0, 57.0, 0.0]
            for index in 0..<3 {
                let rise = easeOutCubic(wrap(time + Double(index) * period / 3, period))
                layer.fill(Path(roundedRect: CGRect(x: lanes[index], y: 50 - 36 * rise, width: 7, height: 7),
                                 cornerRadius: 1.5),
                           with: .color(tone(hues[index], 0.45 + 0.55 * (1 - rise))))
            }
        }
    }

    /// The props each pose shares with the other marks: the cup, the Zs, the
    /// sweat, the stars, the dots, the question mark, the confetti, the ball.
    private static func drawAccessory(_ character: MascotCharacter, pose: MascotPose, time: TimeInterval, colour: Bool,
                                      in context: inout GraphicsContext, size: CGSize, unit: CGFloat) {
        let mono = Color.primary
        let style = Style.of(size: size)
        switch pose {
        case .coffee: drawCoffeeBreak(in: &context, size: size, time: time)
        case .tired: drawSweat(in: &context, size: size, time: time)
        case .spent: drawDizzyStars(in: &context, size: size, time: time)
        case .thinking:
            // The bar's own ink at bar size: the face's navy is invisible on a
            // dark bar.
            drawThoughtDots(in: &context, size: size, time: time,
                            ink: colour && !style.simple ? Face.of(character).ink : mono)
            drawGoldSparks(in: &context, size: size, time: time)
        case .waiting:
            drawQuestionMark(in: &context, size: size, time: time, ink: colour ? Color(hex: 0xFBBC04) : mono)
        case .celebrate: drawConfetti(in: &context, size: size, time: time)
        case .play: drawPlayBall(in: &context, size: size, time: time, ink: colour ? Color(hex: 0xFBBC04) : mono)
        case .error: drawErrorMark(in: &context, size: size, time: time)
        case .testing: drawTestTube(in: &context, size: size, time: time, ink: colour ? nil : mono)
        case .longCommand: drawHourglass(in: &context, size: size, time: time, ink: colour ? nil : mono)
        case .sleep:
            // The design's own Zs: drawn strokes in the character's blue.
            var layer = context
            layer.scaleBy(x: unit, y: unit)
            let hex: UInt32 = character == .cloudGhost ? 0x3941FF : 0x4893FC
            for index in 0..<2 {
                let phase = (time * 0.35 + Double(index) / 2).truncatingRemainder(dividingBy: 1)
                let side = style.simple ? 9 + 3 * phase : 3 + 2 * phase
                let origin = CGPoint(x: (style.simple ? 46 : 49) + 5 * phase, y: (style.simple ? 19 : 17) - 12 * phase)
                var z = Path()
                z.move(to: origin)
                z.addLine(to: CGPoint(x: origin.x + side, y: origin.y))
                z.addLine(to: CGPoint(x: origin.x, y: origin.y + side))
                z.addLine(to: CGPoint(x: origin.x + side, y: origin.y + side))
                layer.stroke(z, with: .color(colour ? Color(hex: hex, opacity: 1 - phase) : mono.opacity(1 - phase)),
                             style: StrokeStyle(lineWidth: style.stroke(style.simple ? 3 : 2), lineCap: .round, lineJoin: .round))
            }
        case .run, .type, .waking, .awake, .stretch: break
        }
    }
}
