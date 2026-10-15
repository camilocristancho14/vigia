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
        /// Codex's `>_` prompt, the cursor blinking.
        case prompt(cursor: Bool)
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

    private static func momentAtFullGain(for pose: MascotPose, character: MascotCharacter, at time: TimeInterval) -> Moment {
        var moment = Moment()
        let blink = time.truncatingRemainder(dividingBy: 4.2) >= 4.05
        switch pose {
        case .run:
            moment.offset.height = -2.2 * abs(sin(time * 9))
            moment.rotation = -5
            moment.eyes = .open(look: CGPoint(x: 1.2, y: 0))
            moment.mouth = .flat
        case .type:
            moment.rotation = 3.5 * sin(time * 2.2)
            moment.offset.height = -0.7 * abs(sin(time * 4.4))
            moment.eyes = character == .cloudGhost
                ? .prompt(cursor: Int(time * 2.4) % 2 == 0)
                : .open(look: CGPoint(x: -1.2, y: 0.6))
            moment.mouth = .flat
        case .thinking:
            moment.rotation = -4 + 1.5 * sin(time * 1.4)
            moment.offset.height = -0.8 * sin(time * 1.8)
            moment.eyes = .open(look: CGPoint(x: 1.1, y: -1.1))
            moment.mouth = .small
        case .waking:
            let beat = time.truncatingRemainder(dividingBy: 3)
            let rise = min(1, beat / 1.6)
            moment.fromFeet = true
            moment.scale = CGSize(width: 1.06 - 0.06 * rise, height: 0.82 + 0.18 * rise)
            moment.eyes = rise < 0.45 ? .closed : rise < 0.8 ? .half : .wide(look: .zero)
            moment.mouth = rise < 0.8 ? .small : .open
        case .waiting:
            let hop = abs(sin(time * 3.2))
            moment.offset.height = -4 * hop
            moment.fromFeet = true
            moment.scale = CGSize(width: 1 + 0.04 * (1 - hop), height: 1 - 0.04 * (1 - hop))
            moment.eyes = .wide(look: CGPoint(x: 0.6, y: -0.9))
            moment.mouth = .small
        case .celebrate:
            moment.offset.height = -5 * abs(sin(time * 5))
            moment.rotation = 8 * sin(time * 10)
            moment.eyes = .happy
            moment.mouth = .open
        case .coffee:
            moment.rotation = 2.5 * sin(time * 1.6)
            moment.eyes = blink ? .closed : .open(look: CGPoint(x: 0.9, y: 0.4))
            moment.mouth = .smile
        case .awake:
            moment.scale = CGSize(width: 1, height: 1 + 0.02 * sin(time * 1.6))
            moment.fromFeet = true
            moment.eyes = blink ? .closed : .open(look: .zero)
            moment.mouth = .smile
        case .stretch:
            let reach = (sin(time * 1.1) + 1) / 2
            moment.fromFeet = true
            moment.scale = CGSize(width: 1 - 0.05 * reach, height: 1 + 0.09 * reach)
            moment.eyes = reach > 0.5 ? .happy : .closed
            moment.mouth = reach > 0.5 ? .open : .small
        case .play:
            let across = playAcross(at: time)
            moment.offset.width = 2 * sin(time * 2.8)
            moment.offset.height = -1.5 * abs(sin(time * 5.6))
            moment.eyes = .open(look: CGPoint(x: (across - 0.5) * 2.4, y: -1))
            moment.mouth = .open
        case .sleep:
            moment.fromFeet = true
            moment.offset.height = 2.5
            moment.rotation = character == .starBuddy ? 8 : 0
            moment.scale = CGSize(width: 1 + 0.015 * sin(time * 0.9), height: 1 - 0.025 * sin(time * 0.9))
            moment.eyes = .closed
            moment.mouth = .small
        case .tired:
            moment.fromFeet = true
            moment.rotation = -6 + 1.5 * sin(time * 1.2)
            moment.offset.height = 1.5
            moment.eyes = .half
            moment.mouth = .flat
        case .spent:
            moment.offset.width = 0.8 * sin(time * 26)
            moment.eyes = .squeezed
            moment.mouth = .frown
        case .testing:
            // Leaning back to watch the tube, eyes on it.
            moment.rotation = -3 + 1 * sin(time * 1.3)
            moment.offset.width = -1.5
            moment.eyes = .open(look: CGPoint(x: 1.3, y: -1.1))
            moment.mouth = .small
        case .longCommand:
            // Waiting it out, eyes on the sand, a slow sway.
            moment.fromFeet = true
            moment.offset.width = -1.5
            moment.rotation = 2 * sin(time * 0.9)
            moment.eyes = blink ? .closed : .open(look: CGPoint(x: 1.2, y: 0.8))
            moment.mouth = .flat
        case .error:
            // Melting: spread at the feet, sunk, grey.
            let sag = (sin(time * 0.8) + 1) / 2
            moment.fromFeet = true
            moment.scale = CGSize(width: 1.08 + 0.04 * sag, height: 0.86 - 0.04 * sag)
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

    /// The arch for a small mark: the same outer curve, with the hollow
    /// under it raised so the legs are heavy instead of two thin strokes.
    private static let archBar = Path({ () -> CGPath in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 54.33, y: 54.67))
        path.addCurve(to: CGPoint(x: 57.8, y: 51.2), control1: CGPoint(x: 57.41, y: 56.98), control2: CGPoint(x: 62.03, y: 55.43))
        path.addCurve(to: CGPoint(x: 32, y: 5), control1: CGPoint(x: 45.09, y: 38.88), control2: CGPoint(x: 47.78, y: 5))
        path.addCurve(to: CGPoint(x: 6.2, y: 51.2), control1: CGPoint(x: 16.22, y: 5), control2: CGPoint(x: 18.91, y: 38.88))
        path.addCurve(to: CGPoint(x: 9.67, y: 54.67), control1: CGPoint(x: 1.58, y: 55.82), control2: CGPoint(x: 6.59, y: 56.98))
        path.addCurve(to: CGPoint(x: 32, y: 45), control1: CGPoint(x: 19, y: 50), control2: CGPoint(x: 21, y: 45))
        path.addCurve(to: CGPoint(x: 54.33, y: 54.67), control1: CGPoint(x: 43, y: 45), control2: CGPoint(x: 45, y: 50))
        path.closeSubpath()
        var lift = CGAffineTransform(translationX: 0, y: -1)
        return path.copy(using: &lift) ?? path
    }())

    /// Antigravity's arch, traced from the official icon, lifted one unit.
    private static let arch = Path({ () -> CGPath in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 54.33, y: 54.67))
        path.addCurve(to: CGPoint(x: 57.8, y: 51.2), control1: CGPoint(x: 57.41, y: 56.98), control2: CGPoint(x: 62.03, y: 55.43))
        path.addCurve(to: CGPoint(x: 32, y: 5), control1: CGPoint(x: 45.09, y: 38.88), control2: CGPoint(x: 47.78, y: 5))
        path.addCurve(to: CGPoint(x: 6.2, y: 51.2), control1: CGPoint(x: 16.22, y: 5), control2: CGPoint(x: 18.91, y: 38.88))
        path.addCurve(to: CGPoint(x: 9.67, y: 54.67), control1: CGPoint(x: 1.58, y: 55.82), control2: CGPoint(x: 6.59, y: 56.98))
        path.addCurve(to: CGPoint(x: 32, y: 38.37), control1: CGPoint(x: 20.6, y: 47.34), control2: CGPoint(x: 21.26, y: 38.37))
        path.addCurve(to: CGPoint(x: 54.33, y: 54.67), control1: CGPoint(x: 42.74, y: 38.37), control2: CGPoint(x: 43.4, y: 47.34))
        path.closeSubpath()
        var lift = CGAffineTransform(translationX: 0, y: -1)
        return path.copy(using: &lift) ?? path
    }())

    /// The Codex cloud: a scalloped ghost hem under five overlapping puffs.
    private static let cloud = Path({ () -> CGPath in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 10, y: 35))
        path.addLine(to: CGPoint(x: 54, y: 35))
        path.addLine(to: CGPoint(x: 54, y: 50))
        for (end, control) in [(43.0, 48.5), (32.0, 37.5), (21.0, 26.5), (10.0, 15.5)] {
            path.addQuadCurve(to: CGPoint(x: end, y: 50), control: CGPoint(x: control, y: 58))
        }
        path.closeSubpath()
        for (x, y, r) in [(17.5, 34.0, 8.5), (25, 23, 10), (39, 22, 10.5), (47, 33, 8.5), (32, 30, 12)] {
            path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
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
            inside.translateBy(x: 0, y: -1)
            var sheen = Path()
            sheen.move(to: CGPoint(x: 43.6, y: 21))
            sheen.addCurve(to: CGPoint(x: 51.2, y: 38.5), control1: CGPoint(x: 44.2, y: 26), control2: CGPoint(x: 45.8, y: 32.5))
            sheen.addLines([CGPoint(x: 62, y: 38.5), CGPoint(x: 62, y: 21)])
            sheen.closeSubpath()
            inside.fill(sheen, with: .color(Color(hex: 0x749BFF, opacity: 0.9)))
            var green = Path()
            green.move(to: CGPoint(x: 4, y: 26.5))
            green.addCurve(to: CGPoint(x: 28.5, y: 13.5), control1: CGPoint(x: 14, y: 25.6), control2: CGPoint(x: 22, y: 21.5))
            green.addLines([CGPoint(x: 28.5, y: 0), CGPoint(x: 4, y: 0)])
            green.closeSubpath()
            inside.fill(green, with: .color(Color(hex: 0x00B95C)))
            var yellow = Path()
            yellow.move(to: CGPoint(x: 14, y: 15))
            yellow.addCurve(to: CGPoint(x: 37.2, y: 16.2), control1: CGPoint(x: 20, y: 13.6), control2: CGPoint(x: 28, y: 13.4))
            yellow.addLines([CGPoint(x: 31, y: 0), CGPoint(x: 14, y: 0)])
            yellow.closeSubpath()
            inside.fill(yellow, with: .color(Color(hex: 0xFBBC04)))
            var red = Path()
            red.move(to: CGPoint(x: 31, y: 0))
            red.addLine(to: CGPoint(x: 37.2, y: 16.2))
            red.addCurve(to: CGPoint(x: 46.6, y: 23.6), control1: CGPoint(x: 40.5, y: 17.6), control2: CGPoint(x: 44, y: 20.2))
            red.addLines([CGPoint(x: 62, y: 27), CGPoint(x: 62, y: 0)])
            red.closeSubpath()
            inside.fill(red, with: .color(Color(hex: 0xFC413D)))
            var shine = inside
            shine.translateBy(x: 26.5, y: 10.5)
            shine.rotate(by: .degrees(-35))
            shine.fill(ellipse(0, 0, 3, 1.5), with: .color(.white.opacity(0.45)))

        default:
            let shape = cloud
            context.stroke(shape, with: .color(Color(hex: 0x262394)),
                           style: StrokeStyle(lineWidth: 4.6, lineJoin: .round))
            context.fill(shape, with: .color(Color(hex: 0x262394)))
            context.fill(shape, with: .linearGradient(
                Gradient(stops: [.init(color: Color(hex: 0xB1A7FF), location: 0),
                                 .init(color: Color(hex: 0x7A9DFF), location: 0.5),
                                 .init(color: Color(hex: 0x3941FF), location: 1)]),
                startPoint: CGPoint(x: 32, y: 11), endPoint: CGPoint(x: 32, y: 56)))
            var shine = context
            shine.translateBy(x: 22, y: 20)
            shine.rotate(by: .degrees(-35))
            shine.fill(ellipse(0, 0, 4.6, 2.4), with: .color(.white.opacity(0.55)))
            context.fill(ellipse(29, 15.5, 1.3, 1.3), with: .color(.white.opacity(0.5)))
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
            inside.translateBy(x: 0, y: -1)
            var green = Path()
            green.move(to: CGPoint(x: 0, y: 29)); green.addLine(to: CGPoint(x: 20, y: 22))
            green.addLine(to: CGPoint(x: 27, y: 10)); green.addLine(to: CGPoint(x: 0, y: 4)); green.closeSubpath()
            inside.fill(green, with: .color(Color(hex: 0x00B95C)))
            var yellow = Path()
            yellow.move(to: CGPoint(x: 14, y: 17)); yellow.addLine(to: CGPoint(x: 38, y: 17))
            yellow.addLine(to: CGPoint(x: 32, y: 0)); yellow.addLine(to: CGPoint(x: 14, y: 0)); yellow.closeSubpath()
            inside.fill(yellow, with: .color(Color(hex: 0xFBBC04)))
            var red = Path()
            red.move(to: CGPoint(x: 32, y: 0)); red.addLine(to: CGPoint(x: 38, y: 17))
            red.addLine(to: CGPoint(x: 48, y: 25)); red.addLine(to: CGPoint(x: 64, y: 26)); red.addLine(to: CGPoint(x: 64, y: 0))
            red.closeSubpath()
            inside.fill(red, with: .color(Color(hex: 0xFC413D)))

        default:
            let shape = cloud
            context.stroke(shape, with: .color(Color(hex: 0x262394)), style: StrokeStyle(lineWidth: 5.6, lineJoin: .round))
            context.fill(shape, with: .color(Color(hex: 0x262394)))
            context.fill(shape, with: .linearGradient(
                Gradient(colors: [Color(hex: 0xA9A4FF), Color(hex: 0x5C7BFF)]),
                startPoint: CGPoint(x: 32, y: 11), endPoint: CGPoint(x: 32, y: 56)))
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

        static func of(_ character: MascotCharacter) -> Face {
            switch character {
            case .starBuddy:
                Face(left: CGPoint(x: 25.5, y: 31), right: CGPoint(x: 38.5, y: 31), blushY: 36.2,
                     blushX: (20.8, 43.2), mouthY: 38.6, feet: 59, ink: Color(hex: 0x231F4A), blush: Color(hex: 0xFF9FB8))
            case .cloudGhost:
                Face(left: CGPoint(x: 24, y: 38), right: CGPoint(x: 40, y: 38), blushY: 43.2,
                     blushX: (19.4, 44.6), mouthY: 45, feet: 56, ink: Color(hex: 0x1A1866), blush: Color(hex: 0xFF9FD6))
            default:
                Face(left: CGPoint(x: 25.8, y: 25.5), right: CGPoint(x: 38.2, y: 25.5), blushY: 30.1,
                     blushX: (21.4, 42.6), mouthY: 33, feet: 56, ink: Color(hex: 0x231F4A), blush: Color(hex: 0xFF9FB8))
            }
        }
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

        if colour, !style.simple, moment.eyes != .cross {
            for x in [face.blushX.0, face.blushX.1] {
                context.fill(ellipse(x, face.blushY, 2.6, 1.7), with: .color(face.blush.opacity(0.8)))
            }
        }

        for (index, eye) in [face.left, face.right].enumerated() {
            switch moment.eyes {
            case .open(let look), .wide(let look):
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
            case .prompt(let cursor):
                // The design's white `>_` across both eyes, drawn once.
                guard index == 0 else { continue }
                let white = GraphicsContext.Shading.color(colour ? .white : .black)
                var chevron = Path()
                chevron.move(to: CGPoint(x: 22.5, y: 34))
                chevron.addLine(to: CGPoint(x: 28, y: 38.5))
                chevron.addLine(to: CGPoint(x: 22.5, y: 43))
                context.stroke(chevron, with: white, style: StrokeStyle(lineWidth: style.stroke(style.simple ? 3.8 : 2.8), lineCap: .round, lineJoin: .round))
                if cursor {
                    var bar = Path()
                    bar.move(to: CGPoint(x: 33, y: 43))
                    bar.addLine(to: CGPoint(x: 41.5, y: 43))
                    context.stroke(bar, with: white, style: StrokeStyle(lineWidth: style.stroke(style.simple ? 3.8 : 2.8), lineCap: .round))
                }
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
    /// sparkles orbit it, Float Bot pulses code chevrons and drops thrust
    /// sparkles from under its arch, Cloud Ghost's data bits rise up its sides.
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
                let radius = 2.4 + 1.1 * sin(angle)
                drawSpark(in: &layer, at: centre, radius: radius, colour: tone(hex, 0.6 + 0.35 * sin(angle)))
            }
        case .floatBot:
            guard front else {
                for index in 0..<3 {
                    let fall = (time * 1.4 * speed + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    let hex: UInt32 = [0xFC413D, 0xFBBC04, 0x00B95C][index]
                    let centre = CGPoint(x: 32 + 3.5 * sin(Double(index) * 2.1 + time), y: 43 + 14 * fall)
                    drawSpark(in: &layer, at: centre, radius: 2.4 * (1 - fall * 0.5), colour: tone(hex, 1 - fall))
                }
                return
            }
            for (index, side) in [-1.0, 1.0].enumerated() {
                let pulse = (sin(time * 4 * speed + Double(index) * .pi) + 1) / 2
                let x = 32 + side * 25
                var chevron = Path()
                chevron.move(to: CGPoint(x: x - side * 0, y: 24.6))
                chevron.addLine(to: CGPoint(x: x + side * 3.4, y: 28))
                chevron.addLine(to: CGPoint(x: x, y: 31.4))
                layer.stroke(chevron, with: .color(tone(0x4893FC, 0.3 + 0.65 * pulse)),
                             style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        default:
            guard !front else { return }
            for index in 0..<4 {
                let rise = (time * 0.7 * speed + Double(index) / 4).truncatingRemainder(dividingBy: 1)
                let x = index % 2 == 0 ? 2.6 : 58.6
                let y = 50 - 32 * rise
                let side = 2.6 + 0.6 * Double(index % 2)
                let hex: UInt32 = index % 3 == 0 ? 0x3941FF : 0x7A9DFF
                layer.fill(Path(roundedRect: CGRect(x: x, y: y, width: side, height: side), cornerRadius: 0.9),
                           with: .color(tone(hex, 1 - rise * 0.7)))
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
                let centre = CGPoint(x: 32 + 23 * cos(angle), y: 33 + 20 * sin(angle))
                drawSpark(in: &layer, at: centre, radius: 7, colour: tone(hue))
            }
        case .floatBot:
            for (index, side) in [-1.0, 1.0].enumerated() {
                let pulse = (sin(time * 5 * speed + Double(index) * .pi) + 1) / 2
                let x = 32 + side * 29
                var chevron = Path()
                chevron.move(to: CGPoint(x: x - side * 2.5, y: 23))
                chevron.addLine(to: CGPoint(x: x + side * 1.5, y: 29))
                chevron.addLine(to: CGPoint(x: x - side * 2.5, y: 35))
                layer.stroke(chevron, with: .color(tone(0x4893FC, 0.35 + 0.65 * pulse)),
                             style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        default:
            for index in 0..<2 {
                let rise = (time * 0.8 * speed + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                let x = index == 0 ? 0.0 : 57.0
                layer.fill(Path(roundedRect: CGRect(x: x, y: 50 - 36 * rise, width: 7, height: 7), cornerRadius: 1.5),
                           with: .color(tone(index == 0 ? 0x3941FF : 0x7A9DFF, 1 - rise * 0.6)))
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
