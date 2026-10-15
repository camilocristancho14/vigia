import SwiftUI

/// A provider's logo given something to do. Providers without a mascot of
/// their own still show what the agent is up to: the logo orbits when it is
/// out looking things up, shimmers while it works at its keys, steams on its
/// break, breathes while it waits, sleeps under floating Zs, droops with a
/// bead of sweat when the limit is nearly gone and shakes among stars when it
/// is gone. It also thinks under counting dots, rises as a turn starts, hops
/// under a question mark when a person has to answer, jumps in confetti when a
/// turn is done, stretches and plays catch while idle, and greys out under a
/// red cross when a turn failed.
struct LogoMascotView: View {
    let provider: Provider
    let pose: MascotPose
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A waiting logo moves slowly, so it is redrawn slowly.
    private var interval: TimeInterval {
        switch pose {
        case .awake, .stretch: 1.0 / 8
        case .sleep, .tired, .error: 1.0 / 10
        default: 1.0 / 24
        }
    }

    var body: some View {
        if reduceMotion {
            LobeIconView(provider: provider, size: size * 0.9)
                .frame(width: size, height: size)
        } else {
            animated
        }
    }

    private var animated: some View {
        let phaseOffset = provider.mascotPhase
        return TimelineView(.animation(minimumInterval: interval)) { context in
            let time = context.date.timeIntervalSinceReferenceDate + phaseOffset
            ZStack {
                logo(at: time)
                Canvas { canvas, canvasSize in
                    overlay(&canvas, canvasSize, time)
                }
                .allowsHitTesting(false)
            }
            .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private func logo(at time: TimeInterval) -> some View {
        let mark = LobeIconView(provider: provider, size: size * 0.9)
        switch pose {
        case .awake:
            mark.scaleEffect(1 + 0.04 * sin(time * 1.6))
        case .run:
            mark.scaleEffect(0.86 + 0.04 * sin(time * 7))
        case .type:
            mark.opacity(0.55)
                .overlay { mark.mask(shimmer(at: time)) }
        case .coffee:
            mark.rotationEffect(.degrees(3 * sin(time * 1.8)))
        case .sleep:
            mark.opacity(0.4).scaleEffect(1 + 0.025 * sin(time * 0.9))
        case .tired:
            mark.rotationEffect(.degrees(-9 + 2 * sin(time * 1.2)), anchor: .bottom)
                .offset(y: size * 0.04).opacity(0.8)
        case .spent:
            mark.opacity(0.5).offset(x: size * 0.04 * sin(time * 28))
        case .thinking:
            mark.scaleEffect(0.9 + 0.03 * sin(time * 2.4)).rotationEffect(.degrees(-4))
        case .waking:
            let rise = min(1, time.truncatingRemainder(dividingBy: 3) / 1.6)
            mark.scaleEffect(0.75 + 0.25 * rise, anchor: .bottom).opacity(0.45 + 0.55 * rise)
        case .waiting:
            mark.scaleEffect(0.86).offset(y: -size * 0.08 * abs(sin(time * 3.2)))
        case .celebrate:
            mark.scaleEffect(0.86).offset(y: -size * 0.1 * abs(sin(time * 5)))
                .rotationEffect(.degrees(8 * sin(time * 10)))
        case .stretch:
            let reach = (sin(time * 1.1) + 1) / 2
            mark.scaleEffect(x: 1 - 0.06 * reach, y: 1 + 0.1 * reach, anchor: .bottom)
        case .play:
            mark.scaleEffect(0.86).offset(x: size * 0.05 * sin(time * 2.8))
        case .error:
            mark.grayscale(1).opacity(0.45).rotationEffect(.degrees(-6), anchor: .bottom)
        case .testing, .longCommand:
            // Stepped back and still, to make room for the tube or the glass.
            mark.scaleEffect(0.8, anchor: .bottomLeading).offset(y: size * 0.02 * sin(time * 1.5))
        }
    }

    /// A band of light crossing the logo, then a pause.
    private func shimmer(at time: TimeInterval) -> LinearGradient {
        let phase = (time * 0.9).truncatingRemainder(dividingBy: 1.6) / 1.6 * 1.6 - 0.3
        return LinearGradient(
            stops: [
                .init(color: .clear, location: max(0, phase - 0.25)),
                .init(color: .white, location: min(1, max(0, phase))),
                .init(color: .clear, location: min(1, phase + 0.25))
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private func overlay(_ canvas: inout GraphicsContext, _ canvasSize: CGSize, _ time: TimeInterval) {
        switch pose {
        case .run:
            // Three beads on a loop round the logo.
            let width: CGFloat = canvasSize.width
            let height: CGFloat = canvasSize.height
            for index in 0..<3 {
                let angle: Double = time * 4.5 + Double(index) * 2 * Double.pi / 3
                let x: CGFloat = width / 2 + CGFloat(cos(angle)) * width * 0.44
                let y: CGFloat = height / 2 + CGFloat(sin(angle)) * height * 0.44
                let radius: CGFloat = width * (0.06 - 0.012 * CGFloat(index))
                let bead = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                let fade: Double = 0.9 - 0.25 * Double(index)
                canvas.fill(bead, with: .color(.primary.opacity(fade)))
            }
        case .coffee:
            let width: CGFloat = canvasSize.width
            let height: CGFloat = canvasSize.height
            for index in 0..<2 {
                let x: CGFloat = width * (0.4 + 0.2 * CGFloat(index))
                var steam = Path()
                steam.move(to: CGPoint(x: x, y: height * 0.1))
                for step in 1...5 {
                    let progress: Double = Double(step) / 5
                    let phase: Double = time * 2.4 + progress * 4 + Double(index) * 1.9
                    let wave: CGFloat = CGFloat(sin(phase)) * width * 0.04
                    steam.addLine(to: CGPoint(x: x + wave, y: height * (0.1 - 0.1 * CGFloat(progress))))
                }
                canvas.stroke(steam, with: .color(.primary.opacity(0.55)),
                              style: StrokeStyle(lineWidth: max(1, width * 0.05), lineCap: .round))
            }
        case .sleep: drawSleepZs(in: &canvas, size: canvasSize, time: time)
        case .tired: drawSweat(in: &canvas, size: canvasSize, time: time)
        case .spent: drawDizzyStars(in: &canvas, size: canvasSize, time: time)
        case .thinking: drawThoughtDots(in: &canvas, size: canvasSize, time: time, ink: .primary)
        case .waiting: drawQuestionMark(in: &canvas, size: canvasSize, time: time, ink: .primary)
        case .celebrate: drawConfetti(in: &canvas, size: canvasSize, time: time)
        case .play: drawPlayBall(in: &canvas, size: canvasSize, time: time, ink: .primary)
        case .error: drawErrorMark(in: &canvas, size: canvasSize, time: time)
        case .testing: drawTestTube(in: &canvas, size: canvasSize, time: time, ink: .primary)
        case .longCommand: drawHourglass(in: &canvas, size: canvasSize, time: time, ink: .primary)
        case .type, .awake, .waking, .stretch: break
        }
    }
}
