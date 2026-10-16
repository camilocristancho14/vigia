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
        case .sleep, .tired, .error, .awake, .stretch: 1.0 / 12
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
        return moment
    }

    // MARK: - Beats
    //
    // Clawd holds a frame, then the next; the bot eases a squash into a landing.
    // These marks do the same kind of acting, each in its own weight: the arch
    // is nearly weightless, the cloud is a pillow, the star is a buoy.

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

    private static func easeInCubic(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return t * t * t
    }

    /// Shut for the last fifth of a second in every 4.2, the way Clawd blinks.
    private static func eyeBlink(_ time: TimeInterval) -> Bool {
        time.truncatingRemainder(dividingBy: 4.2) >= 4.0
    }

    /// A terminal cursor: lit longer than dark, and quicker while keys are going.
    private static func cursorLit(_ time: TimeInterval, typing: Bool) -> Bool {
        let period = typing ? 0.70 : 1.06
        let lit = typing ? 0.42 : 0.68
        return time.truncatingRemainder(dividingBy: period) < lit
    }

    /// One hump a period, lingering at the top. 0 on the ground, 1 at the crest.
    private static func hoverArc(_ time: TimeInterval, period: Double) -> Double {
        let s = max(0, sin(wrap(time, period) * .pi))
        let u = 1 - s
        return 1 - u * u * u
    }

    /// Crouch, rise, hang, land. Height is 0 on the ground, 1 at the crest and
    /// negative in the crouch. Squash is positive when the body is wide and short.
    /// `weight` is 0 for something with no mass and 1 for a pillow.
    private static func bounce(_ time: TimeInterval, period: Double, hang: Double, weight: Double) -> (height: Double, squash: Double) {
        let t = wrap(time, period)
        let crouch = 0.12 + 0.10 * weight
        if t < crouch {
            let u = smooth(t / crouch)
            return (-0.22 * weight * u, (0.035 + 0.05 * weight) * u)
        }
        let riseEnd = min(0.70, crouch + 0.28 * (1 - hang))
        let hangEnd = min(0.86, riseEnd + max(0, hang))
        if t < riseEnd {
            let u = easeOutCubic((t - crouch) / max(0.001, riseEnd - crouch))
            return (u, -0.04 * (1 - u))
        }
        if t < hangEnd {
            let u = (t - riseEnd) / max(0.001, hangEnd - riseEnd)
            return (1 - 0.035 * sin(u * .pi), -0.012)
        }
        let u = easeInCubic((t - hangEnd) / max(0.001, 1 - hangEnd))
        let land = u > 0.7 ? smooth((u - 0.7) / 0.3) : 0
        return (1 - u, (0.045 + 0.04 * weight) * land)
    }

    /// Longer in than out. 0 empty, 1 full.
    private static func breath(_ time: TimeInterval, period: Double = 3.6) -> Double {
        let t = wrap(time, period)
        if t < 0.62 { return smooth(t / 0.62) }
        return 1 - smooth((t - 0.62) / 0.38)
    }

    private static func momentAtFullGain(for pose: MascotPose, character: MascotCharacter, at time: TimeInterval) -> Moment {
        switch character {
        case .cloudGhost: codexMoment(pose, at: time)
        case .starBuddy: starMoment(pose, at: time)
        default: antigravityMoment(pose, at: time)
        }
    }

    /// Float Bot: almost no weight. It hangs in the air, and thrust is what
    /// brings it down onto a landing.
    private static func antigravityMoment(_ pose: MascotPose, at time: TimeInterval) -> Moment {
        var moment = Moment()
        let blink = eyeBlink(time)
        switch pose {
        case .awake:
            let up = hoverArc(time, period: 2.7)
            moment.offset.height = -1.8 * up
            moment.rotation = 1.8 * sin(wrap(time, 3.4) * 2 * .pi)
            moment.scale = CGSize(width: 1.035 - 0.055 * up, height: 0.975 + 0.055 * up)
            moment.eyes = blink ? .closed : .open(look: .zero)
            moment.mouth = .smile
        case .run:
            let jump = bounce(time, period: 0.48, hang: 0.30, weight: 0.15)
            moment.offset.height = -3.6 * max(0, jump.height) + 0.3 * min(0, jump.height)
            moment.rotation = -7.5 + 1.6 * sin(time * 6)
            moment.scale = CGSize(width: 1 + jump.squash, height: 1 - jump.squash)
            moment.eyes = .open(look: CGPoint(x: 1.5, y: -0.15))
            moment.mouth = .flat
        case .type:
            let tap = hoverArc(time, period: 0.36)
            moment.offset.height = -0.9 * tap
            moment.rotation = 2.6 * sin(time * 1.7)
            moment.scale = CGSize(width: 1 + 0.035 * tap, height: 1 - 0.03 * tap)
            moment.eyes = blink ? .closed : .open(look: CGPoint(x: -1.3, y: 0.7))
            moment.mouth = .flat
        case .thinking:
            let beat = wrap(time, 3.4)
            let lookX = beat < 0.5 ? 1.35 : beat < 0.78 ? 0.15 : -0.9
            let lookY = beat < 0.5 ? -1.35 : -0.35
            moment.rotation = -6.5 + 2.2 * sin(time * 1.05)
            moment.offset.height = -1.5 * hoverArc(time, period: 3.0)
            moment.eyes = blink ? .closed : .open(look: CGPoint(x: lookX, y: lookY))
            moment.mouth = .small
        case .waking:
            // The same three beats Clawd uses: crouched, half open, up.
            let beat = time.truncatingRemainder(dividingBy: 3)
            moment.fromFeet = true
            if beat < 1 {
                moment.scale = CGSize(width: 1.08, height: 0.78 + 0.04 * smooth(beat))
                moment.eyes = .closed
                moment.mouth = .small
            } else if beat < 1.8 {
                let u = smooth((beat - 1) / 0.8)
                moment.scale = CGSize(width: 1.06 - 0.04 * u, height: 0.84 + 0.12 * u)
                moment.offset.height = -0.7 * u
                moment.eyes = .half
                moment.mouth = .small
            } else {
                let u = smooth((beat - 1.8) / 1.2)
                moment.scale = CGSize(width: 1.02 - 0.02 * u, height: 0.96 + 0.04 * u)
                moment.offset.height = -1.5 * u
                moment.eyes = .wide(look: .zero)
                moment.mouth = .open
            }
        case .waiting:
            let jump = bounce(time, period: 0.92, hang: 0.34, weight: 0.12)
            moment.offset.height = -4.6 * max(0, jump.height) + 0.25 * min(0, jump.height)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1 + jump.squash, height: 1 - jump.squash)
            moment.rotation = 2.2 * sin(time * 2.1)
            moment.eyes = .wide(look: CGPoint(x: 0.5, y: -1.1))
            moment.mouth = .small
        case .celebrate:
            let jump = bounce(time, period: 0.52, hang: 0.22, weight: 0.08)
            moment.offset.height = -5.4 * max(0, jump.height)
            moment.rotation = 7.5 * sin(time * 6) * (0.35 + 0.65 * max(0, jump.height))
            moment.scale = CGSize(width: 1 + jump.squash, height: 1 - jump.squash)
            moment.eyes = .happy
            moment.mouth = .open
        case .coffee:
            // Steam, steam, then a sip, as Clawd's cup cycle does.
            let beat = time.truncatingRemainder(dividingBy: 4.2)
            let sip = beat > 2.15 && beat < 2.85
            moment.rotation = 3.2 * sin(time * 1.35) + (sip ? 2 : 0)
            moment.offset.height = -0.7 * hoverArc(time, period: 2.4)
            moment.offset.width = 0.5
            moment.eyes = sip ? .happy : (blink ? .closed : .open(look: CGPoint(x: 1.1, y: 0.35)))
            moment.mouth = sip ? .open : .smile
        case .stretch:
            let cycle = wrap(time, 2.8)
            let reach: Double
            if cycle < 0.16 {
                reach = -0.4 * smooth(cycle / 0.16)
            } else if cycle < 0.62 {
                reach = smooth((cycle - 0.16) / 0.46)
            } else {
                reach = 1 - smooth((cycle - 0.62) / 0.38)
            }
            let up = max(0, reach)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1 - 0.06 * up + 0.045 * max(0, -reach),
                                  height: 1 + 0.10 * up - 0.05 * max(0, -reach))
            moment.eyes = up > 0.55 ? .happy : .closed
            moment.mouth = up > 0.55 ? .open : .small
        case .play:
            let across = playAcross(at: time)
            moment.offset.width = 2.2 * sin(time * 2.6)
            moment.offset.height = -1.7 * hoverArc(time, period: 0.52)
            moment.eyes = .open(look: CGPoint(x: (across - 0.5) * 2.6, y: -1.1))
            moment.mouth = .open
        case .sleep:
            let air = breath(time, period: 4.4)
            moment.fromFeet = true
            moment.offset.height = 1.7 - 0.3 * air
            moment.scale = CGSize(width: 1.02 - 0.03 * air, height: 0.98 + 0.04 * air)
            moment.eyes = .closed
            moment.mouth = .small
        case .tired:
            let air = breath(time, period: 2.8)
            moment.fromFeet = true
            moment.rotation = -7.5 + 1.3 * sin(time * 0.85)
            moment.offset.height = 2
            moment.scale = CGSize(width: 1.045 - 0.02 * air, height: 0.955 + 0.02 * air)
            moment.eyes = .half
            moment.mouth = .flat
        case .spent:
            moment.offset.width = 0.9 * sin(time * 26)
            moment.scale = CGSize(width: 1.04, height: 0.96)
            moment.eyes = .squeezed
            moment.mouth = .frown
        case .testing:
            moment.rotation = -4.2 + 1.5 * sin(time * 1.2)
            moment.offset.width = -1.2
            moment.offset.height = -1.1 * hoverArc(time, period: 2.2)
            moment.eyes = blink ? .closed : .open(look: CGPoint(x: 1.45, y: -1.15))
            moment.mouth = .small
        case .longCommand:
            moment.fromFeet = true
            moment.offset.width = -1.2
            moment.rotation = 2.6 * sin(time * 0.8)
            moment.offset.height = 0.35
            moment.eyes = blink ? .closed : .open(look: CGPoint(x: 1.3, y: 0.95))
            moment.mouth = .flat
        case .error:
            let sag = breath(time, period: 2.4)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1.10 + 0.045 * sag, height: 0.84 - 0.045 * sag)
            moment.eyes = .cross
            moment.mouth = .frown
            moment.grey = true
        }
        return moment
    }

    /// Cloud Ghost: a pillow. Landings squash, the `>_` is the face, and the
    /// cursor — not an eyelid — is what blinks while it is awake.
    private static func codexMoment(_ pose: MascotPose, at time: TimeInterval) -> Moment {
        var moment = Moment()
        let blink = eyeBlink(time)
        func prompt(_ look: CGPoint, typing: Bool = false) -> Eyes {
            .prompt(cursor: cursorLit(time, typing: typing), look: look)
        }
        switch pose {
        case .awake:
            let up = hoverArc(time, period: 3.5)
            moment.offset.height = -1.35 * up
            moment.offset.width = 1.6 * sin(wrap(time, 4.8) * 2 * .pi)
            moment.scale = CGSize(width: 1.055 - 0.07 * up, height: 0.955 + 0.08 * up)
            moment.eyes = prompt(.zero)
            moment.mouth = .smile
        case .run:
            let jump = bounce(time, period: 0.66, hang: 0.14, weight: 0.8)
            moment.offset.height = -2.7 * max(0, jump.height)
            moment.offset.width = 1.5 * sin(time * 2.3)
            moment.rotation = -4.5
            moment.scale = CGSize(width: 1 + 1.2 * jump.squash, height: 1 - 1.2 * jump.squash)
            moment.eyes = prompt(CGPoint(x: 1.15, y: 0))
            moment.mouth = .flat
        case .type:
            let tap = hoverArc(time, period: 0.32)
            moment.offset.height = -0.75 * tap
            moment.rotation = 2.0 * sin(time * 1.45)
            moment.scale = CGSize(width: 1 + 0.05 * tap, height: 1 - 0.045 * tap)
            moment.eyes = prompt(CGPoint(x: -0.75, y: 0.4), typing: true)
            moment.mouth = .flat
        case .thinking:
            let beat = wrap(time, 3.6)
            let look = beat < 0.55 ? CGPoint(x: 0.95, y: -0.85) : CGPoint(x: -0.45, y: -0.25)
            moment.rotation = -5.5 + 1.8 * sin(time * 0.85)
            moment.offset.height = -1.15 * hoverArc(time, period: 3.2)
            moment.offset.width = 0.9 * sin(time * 0.65)
            moment.eyes = prompt(look)
            moment.mouth = .small
        case .waking:
            let beat = time.truncatingRemainder(dividingBy: 3)
            moment.fromFeet = true
            if beat < 1 {
                moment.scale = CGSize(width: 1.12, height: 0.74 + 0.04 * smooth(beat))
                moment.offset.height = 1.2
                moment.eyes = .closed
                moment.mouth = .small
            } else if beat < 1.8 {
                let u = smooth((beat - 1) / 0.8)
                moment.scale = CGSize(width: 1.10 - 0.06 * u, height: 0.80 + 0.14 * u)
                moment.offset.height = 1.2 * (1 - u)
                moment.eyes = .half
                moment.mouth = .small
            } else {
                let u = smooth((beat - 1.8) / 1.2)
                moment.scale = CGSize(width: 1.04 - 0.03 * u, height: 0.96 + 0.04 * u)
                moment.offset.height = -0.8 * u
                moment.eyes = prompt(.zero)
                moment.mouth = .small
            }
        case .waiting:
            let jump = bounce(time, period: 1.08, hang: 0.18, weight: 0.9)
            moment.offset.height = -3.8 * max(0, jump.height)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1 + 1.25 * jump.squash, height: 1 - 1.25 * jump.squash)
            moment.rotation = 1.4 * sin(time * 1.6)
            moment.eyes = prompt(CGPoint(x: 0.45, y: -0.75))
            moment.mouth = .small
        case .celebrate:
            let jump = bounce(time, period: 0.58, hang: 0.16, weight: 0.55)
            moment.offset.height = -4.8 * max(0, jump.height)
            moment.rotation = 6 * sin(time * 5)
            moment.scale = CGSize(width: 1 + 1.1 * jump.squash, height: 1 - 1.1 * jump.squash)
            moment.eyes = .happy
            moment.mouth = .open
        case .coffee:
            let beat = time.truncatingRemainder(dividingBy: 4.2)
            let sip = beat > 2.15 && beat < 2.85
            moment.rotation = 2.8 * sin(time * 1.1)
            moment.offset.width = 0.9 * sin(time * 0.75)
            moment.offset.height = -0.85 * hoverArc(time, period: 2.9)
            moment.scale = CGSize(width: 1.03, height: 0.98)
            moment.eyes = sip ? .happy : prompt(CGPoint(x: 0.9, y: 0.3))
            moment.mouth = sip ? .open : .smile
        case .stretch:
            let cycle = wrap(time, 3.1)
            let reach: Double = cycle < 0.2 ? -0.5 * smooth(cycle / 0.2)
                : cycle < 0.65 ? smooth((cycle - 0.2) / 0.45)
                : 1 - smooth((cycle - 0.65) / 0.35)
            let up = max(0, reach)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1.04 - 0.08 * up + 0.06 * max(0, -reach),
                                  height: 0.98 + 0.12 * up - 0.06 * max(0, -reach))
            moment.eyes = up > 0.55 ? .happy : .closed
            moment.mouth = up > 0.55 ? .open : .small
        case .play:
            let across = playAcross(at: time)
            moment.offset.width = 2.4 * sin(time * 2.2)
            moment.offset.height = -1.2 * hoverArc(time, period: 0.7)
            moment.scale = CGSize(width: 1.04, height: 0.97)
            moment.eyes = prompt(CGPoint(x: (across - 0.5) * 1.8, y: -0.55))
            moment.mouth = .open
        case .sleep:
            let air = breath(time, period: 4.6)
            moment.fromFeet = true
            moment.offset.height = 3.1 - 0.35 * air
            moment.scale = CGSize(width: 1.06 - 0.05 * air, height: 0.94 + 0.06 * air)
            moment.eyes = .closed
            moment.mouth = .small
        case .tired:
            let air = breath(time, period: 3.0)
            moment.fromFeet = true
            moment.rotation = -8 + 1.1 * sin(time * 0.7)
            moment.offset.height = 2.4
            moment.scale = CGSize(width: 1.07 - 0.02 * air, height: 0.93 + 0.025 * air)
            moment.eyes = .half
            moment.mouth = .flat
        case .spent:
            moment.offset.width = 1.0 * sin(time * 24)
            moment.scale = CGSize(width: 1.06, height: 0.93)
            moment.eyes = .squeezed
            moment.mouth = .frown
        case .testing:
            moment.rotation = -3.5 + 1.2 * sin(time * 1.1)
            moment.offset.width = -1.4 + 0.6 * sin(time * 0.8)
            moment.offset.height = -0.7 * hoverArc(time, period: 2.6)
            moment.eyes = prompt(CGPoint(x: 1.2, y: -0.7))
            moment.mouth = .small
        case .longCommand:
            moment.fromFeet = true
            moment.offset.width = -1.3
            moment.rotation = 2.2 * sin(time * 0.7)
            moment.offset.height = 0.8
            moment.scale = CGSize(width: 1.03, height: 0.98)
            moment.eyes = blink ? .closed : prompt(CGPoint(x: 1.05, y: 0.7))
            moment.mouth = .flat
        case .error:
            let sag = breath(time, period: 2.6)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1.12 + 0.05 * sag, height: 0.80 - 0.05 * sag)
            moment.eyes = .cross
            moment.mouth = .frown
            moment.grey = true
        }
        return moment
    }

    /// Star Buddy: a buoy. Quicker than the cloud, with a glint in the scale,
    /// and it tips over when it sleeps.
    private static func starMoment(_ pose: MascotPose, at time: TimeInterval) -> Moment {
        var moment = Moment()
        let blink = eyeBlink(time)
        let glint = 0.02 * sin(time * 5.5)
        switch pose {
        case .awake:
            let up = hoverArc(time, period: 2.4)
            moment.offset.height = -1.4 * up
            moment.rotation = 2.4 * sin(wrap(time, 3.2) * 2 * .pi)
            moment.scale = CGSize(width: 1 + glint, height: 1 + 0.03 * up - glint)
            moment.fromFeet = true
            moment.eyes = blink ? .closed : .open(look: .zero)
            moment.mouth = .smile
        case .run:
            let jump = bounce(time, period: 0.42, hang: 0.18, weight: 0.25)
            moment.offset.height = -3.2 * max(0, jump.height)
            moment.rotation = -6
            moment.scale = CGSize(width: 1 + jump.squash + glint, height: 1 - jump.squash)
            moment.eyes = .open(look: CGPoint(x: 1.4, y: 0))
            moment.mouth = .flat
        case .type:
            let tap = hoverArc(time, period: 0.34)
            moment.offset.height = -0.8 * tap
            moment.rotation = 3.2 * sin(time * 2.0)
            moment.scale = CGSize(width: 1 + glint, height: 1 - 0.02 * tap)
            moment.eyes = blink ? .closed : .open(look: CGPoint(x: -1.2, y: 0.55))
            moment.mouth = .flat
        case .thinking:
            let beat = wrap(time, 3.2)
            moment.rotation = -5 + 2 * sin(time * 1.2)
            moment.offset.height = -1.2 * hoverArc(time, period: 2.6)
            moment.eyes = blink ? .closed : .open(look: CGPoint(x: beat < 0.6 ? 1.2 : -0.6, y: -1.2))
            moment.mouth = .small
        case .waking:
            let beat = time.truncatingRemainder(dividingBy: 3)
            moment.fromFeet = true
            if beat < 1 {
                moment.scale = CGSize(width: 1.08, height: 0.80)
                moment.eyes = .closed
                moment.mouth = .small
            } else if beat < 1.8 {
                let u = smooth((beat - 1) / 0.8)
                moment.scale = CGSize(width: 1.05 - 0.03 * u, height: 0.86 + 0.10 * u)
                moment.eyes = .half
                moment.mouth = .small
            } else {
                moment.scale = CGSize(width: 1, height: 1)
                moment.offset.height = -1.2 * smooth((beat - 1.8) / 1.2)
                moment.eyes = .wide(look: .zero)
                moment.mouth = .open
            }
        case .waiting:
            let jump = bounce(time, period: 0.84, hang: 0.26, weight: 0.3)
            moment.offset.height = -4.4 * max(0, jump.height)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1 + jump.squash, height: 1 - jump.squash)
            moment.eyes = .wide(look: CGPoint(x: 0.6, y: -1.0))
            moment.mouth = .small
        case .celebrate:
            let jump = bounce(time, period: 0.48, hang: 0.2, weight: 0.2)
            moment.offset.height = -5.2 * max(0, jump.height)
            moment.rotation = 8 * sin(time * 5.5)
            moment.scale = CGSize(width: 1 + jump.squash + glint, height: 1 - jump.squash)
            moment.eyes = .happy
            moment.mouth = .open
        case .coffee:
            let beat = time.truncatingRemainder(dividingBy: 4.2)
            let sip = beat > 2.15 && beat < 2.85
            moment.rotation = 2.8 * sin(time * 1.5)
            moment.eyes = sip ? .happy : (blink ? .closed : .open(look: CGPoint(x: 1.0, y: 0.4)))
            moment.mouth = sip ? .open : .smile
        case .stretch:
            let reach = hoverArc(time, period: 2.6)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1 - 0.05 * reach, height: 1 + 0.09 * reach)
            moment.eyes = reach > 0.55 ? .happy : .closed
            moment.mouth = reach > 0.55 ? .open : .small
        case .play:
            let across = playAcross(at: time)
            moment.offset.width = 2.3 * sin(time * 2.8)
            moment.offset.height = -1.6 * hoverArc(time, period: 0.48)
            moment.eyes = .open(look: CGPoint(x: (across - 0.5) * 2.5, y: -1))
            moment.mouth = .open
        case .sleep:
            let air = breath(time, period: 4.0)
            moment.fromFeet = true
            moment.offset.height = 2.2
            moment.rotation = 8
            moment.scale = CGSize(width: 1.02 - 0.02 * air, height: 0.98 + 0.03 * air)
            moment.eyes = .closed
            moment.mouth = .small
        case .tired:
            moment.fromFeet = true
            moment.rotation = -6 + 1.6 * sin(time * 1.1)
            moment.offset.height = 1.6
            moment.eyes = .half
            moment.mouth = .flat
        case .spent:
            moment.offset.width = 0.85 * sin(time * 26)
            moment.rotation = 3 * sin(time * 13)
            moment.eyes = .squeezed
            moment.mouth = .frown
        case .testing:
            moment.rotation = -3.2 + sin(time * 1.3)
            moment.offset.width = -1.4
            moment.eyes = blink ? .closed : .open(look: CGPoint(x: 1.35, y: -1.1))
            moment.mouth = .small
        case .longCommand:
            moment.fromFeet = true
            moment.offset.width = -1.4
            moment.rotation = 2.2 * sin(time * 0.9)
            moment.eyes = blink ? .closed : .open(look: CGPoint(x: 1.2, y: 0.85))
            moment.mouth = .flat
        case .error:
            let sag = breath(time, period: 2.2)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1.09 + 0.04 * sag, height: 0.85 - 0.04 * sag)
            moment.rotation = 4 * sin(time * 1.4)
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
        case .cloudGhost: (1.12, CGPoint(x: 31, y: 33.5))
        default: (1.04, CGPoint(x: 32, y: 30.5))
        }
    }

    static func draw(_ character: MascotCharacter, pose: MascotPose, time: TimeInterval, colour: Bool,
                     in context: inout GraphicsContext, size: CGSize) {
        let style = Style.of(size: size)
        let moment = moment(for: pose, character: character, at: time, gain: style.simple ? 1.8 : 1)
        let unit = min(size.width, size.height) / 64
        let face = Face.of(character)
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

        static func of(_ character: MascotCharacter) -> Face {
            switch character {
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
    private static func drawLogoPrompt(cursor: Bool, offset: CGPoint, colour: Bool,
                                       in context: inout GraphicsContext) {
        var layer = context
        layer.translateBy(x: offset.x, y: offset.y)
        if colour { layer.blendMode = .destinationOut }
        let ink = GraphicsContext.Shading.color(.black)
        layer.fill(codexChevron, with: ink)
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
                    drawLogoPrompt(cursor: true, offset: look, colour: colour, in: &context)
                    continue
                }
                let wide = { if case .wide = moment.eyes { return true } else { return false } }()
                let centre = CGPoint(x: eye.x + look.x, y: eye.y + look.y)
                context.fill(ellipse(centre.x, centre.y, (wide ? 3.3 : 3) * grow, (wide ? 4.4 : 4) * grow), with: ink)
                if colour, !style.simple {
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
                drawLogoPrompt(cursor: cursor, offset: look, colour: colour, in: &context)
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
