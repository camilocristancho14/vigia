import SwiftUI

/// What is drawn over the mark for the pose it is in, on top of the upstream
/// face: the cup, the laptop, the speed lines, the sweat, the stars and the
/// sleeper's Zs. The faces themselves are the upstream's states.
func drawMascotOverlay(pose: MascotPose, mood: BotMarkMood, in context: inout GraphicsContext,
                       size: CGSize, time: TimeInterval) {
    switch (pose, mood) {
    case (.coffee, .idle): drawCoffeeBreak(in: &context, size: size, time: time)
    case (.type, .working), (.type, .idle): drawLaptop(in: &context, size: size, time: time)
    case (.run, .working), (.run, .idle): drawSpeedLines(in: &context, size: size, time: time)
    case (.tired, .idle): drawSweat(in: &context, size: size, time: time)
    case (.spent, _): drawDizzyStars(in: &context, size: size, time: time)
    case (.sleep, .idle): drawSleepZs(in: &context, size: size, time: time)
    case (.thinking, _):
        drawThoughtDots(in: &context, size: size, time: time, ink: overlayInk)
        drawGoldSparks(in: &context, size: size, time: time)
    case (.waiting, _): drawQuestionMark(in: &context, size: size, time: time, ink: Color(red: 0.98, green: 0.74, blue: 0.02))
    case (.celebrate, _): drawConfetti(in: &context, size: size, time: time)
    case (.play, _): drawPlayBall(in: &context, size: size, time: time, ink: Color(red: 0.98, green: 0.74, blue: 0.02))
    case (.error, _): drawErrorMark(in: &context, size: size, time: time)
    default: break
    }
}

private let overlayInk = Color(red: 0.34, green: 0.21, blue: 0.14)

/// A laptop in front of the mark, its lid towards us, keys going.
private func drawLaptop(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
    let width = size.width, height = size.height
    let tap = sin(time * 14) * height * 0.012
    let lid = CGRect(x: width * 0.22, y: height * 0.66 + tap, width: width * 0.56, height: height * 0.24)
    let line = max(1, width * 0.035)
    let shape = Path(roundedRect: lid, cornerRadius: width * 0.04)
    context.fill(shape, with: .color(Color(white: 0.80)))
    context.stroke(shape, with: .color(overlayInk), lineWidth: line)
    let base = CGRect(x: width * 0.16, y: lid.maxY, width: width * 0.68, height: height * 0.045)
    context.fill(Path(roundedRect: base, cornerRadius: width * 0.02), with: .color(Color(white: 0.55)))
    context.stroke(Path(roundedRect: base, cornerRadius: width * 0.02), with: .color(overlayInk), lineWidth: line * 0.8)
    // The logo on the lid blinks as the keys go.
    let lit = Int(time * 5) % 2 == 0
    let logo = CGRect(x: lid.midX - width * 0.035, y: lid.midY - width * 0.035, width: width * 0.07, height: width * 0.07)
    context.fill(Path(ellipseIn: logo), with: .color(lit ? .white : Color(white: 0.6)))
}

/// Streaks trailing behind, as if it were off somewhere in a hurry.
private func drawSpeedLines(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
    let width: CGFloat = size.width
    let height: CGFloat = size.height
    for index in 0..<3 {
        let phase: Double = (time * 1.6 + Double(index) * 0.33).truncatingRemainder(dividingBy: 1)
        let y: CGFloat = height * (0.34 + 0.16 * CGFloat(index))
        let start: CGFloat = width * (0.16 - 0.14 * CGFloat(phase))
        let length: CGFloat = width * (0.12 + 0.05 * CGFloat(index % 2))
        var path = Path()
        path.move(to: CGPoint(x: start, y: y))
        path.addLine(to: CGPoint(x: start - length, y: y))
        let fade: Double = 0.55 * (1 - phase)
        context.stroke(path, with: .color(overlayInk.opacity(fade)),
                       style: StrokeStyle(lineWidth: max(1, width * 0.04), lineCap: .round))
    }
}

/// A drop of sweat running down the side of the head.
func drawSweat(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
    let width: CGFloat = size.width
    let height: CGFloat = size.height
    let phase: CGFloat = CGFloat((time * 0.55).truncatingRemainder(dividingBy: 1))
    let centre = CGPoint(x: width * 0.84, y: height * (0.14 + 0.5 * phase))
    let radius: CGFloat = width * 0.045
    let top = CGPoint(x: centre.x, y: centre.y - radius * 2.2)
    var drop = Path()
    drop.move(to: top)
    drop.addQuadCurve(to: CGPoint(x: centre.x + radius, y: centre.y),
                      control: CGPoint(x: centre.x + radius * 0.4, y: centre.y - radius))
    drop.addArc(center: centre, radius: radius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
    drop.addQuadCurve(to: top, control: CGPoint(x: centre.x - radius * 0.4, y: centre.y - radius))
    let fade: Double = 1 - Double(phase) * 0.5
    context.fill(drop, with: .color(Color(red: 0.47, green: 0.78, blue: 0.96).opacity(fade)))
}

/// Stars wheeling round the head: nothing left to give.
func drawDizzyStars(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
    let width: CGFloat = size.width
    let height: CGFloat = size.height
    let radius: CGFloat = width * 0.05
    for index in 0..<3 {
        let angle: Double = time * 2.2 + Double(index) * 2 * Double.pi / 3
        let dx: CGFloat = CGFloat(cos(angle)) * width * 0.3
        let dy: CGFloat = CGFloat(sin(angle)) * height * 0.05
        let centre = CGPoint(x: width * 0.5 + dx, y: height * 0.1 + dy)
        var star = Path()
        for point in 0..<8 {
            let reach: CGFloat = point % 2 == 0 ? radius : radius * 0.4
            let turn: Double = Double(point) * Double.pi / 4 - Double.pi / 2
            let corner = CGPoint(x: centre.x + CGFloat(cos(turn)) * reach,
                                 y: centre.y + CGFloat(sin(turn)) * reach)
            if point == 0 { star.move(to: corner) } else { star.addLine(to: corner) }
        }
        star.closeSubpath()
        context.fill(star, with: .color(Color(red: 0.98, green: 0.8, blue: 0.08)))
    }
}

/// Zs drifting up and fading out.
func drawSleepZs(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
    let width: CGFloat = size.width
    let height: CGFloat = size.height
    for index in 0..<3 {
        let phase: Double = (time * 0.35 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
        let fontSize: CGFloat = width * (0.14 + 0.06 * CGFloat(phase))
        let colour = Color(red: 0.55, green: 0.65, blue: 0.95).opacity(1 - phase)
        let letter = Text("z").font(.system(size: fontSize, weight: .bold, design: .rounded)).foregroundColor(colour)
        let x: CGFloat = width * (0.74 + 0.08 * CGFloat(phase))
        let y: CGFloat = height * (0.3 - 0.22 * CGFloat(phase))
        context.draw(letter, at: CGPoint(x: x, y: y))
    }
}

/// A cup of coffee steaming in the corner of the mark: what it does between
/// turns. Drawn over the mark rather than as one of its upstream states, which
/// are all faces. Outlined, so it reads on the light menu bar as well as on the
/// dark disc behind the rings.
func drawCoffeeBreak(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
    let width = size.width, height = size.height
    let ink = Color(red: 0.34, green: 0.21, blue: 0.14)
    let mug = CGRect(x: width * 0.60, y: height * 0.64, width: width * 0.28, height: height * 0.24)
    let line = max(1, width * 0.04)

    var handle = Path()
    handle.addArc(center: CGPoint(x: mug.maxX, y: mug.midY), radius: mug.height * 0.26,
                  startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
    context.stroke(handle, with: .color(ink), lineWidth: line * 1.8)
    context.stroke(handle, with: .color(.white), lineWidth: line)

    let body = Path(roundedRect: mug, cornerRadius: width * 0.04)
    context.fill(body, with: .color(.white))
    context.fill(
        Path(roundedRect: CGRect(x: mug.minX, y: mug.minY, width: mug.width, height: mug.height * 0.3),
             cornerRadius: width * 0.03),
        with: .color(ink)
    )
    context.stroke(body, with: .color(ink), lineWidth: line)

    for index in 0..<2 {
        let x: CGFloat = mug.minX + mug.width * (0.32 + 0.36 * CGFloat(index))
        var steam = Path()
        steam.move(to: CGPoint(x: x, y: mug.minY - 1))
        for step in 1...6 {
            let progress: Double = Double(step) / 6
            let phase: Double = time * 2.4 + progress * 4 + Double(index) * 1.7
            let wave: CGFloat = CGFloat(sin(phase)) * width * 0.025
            let rise: CGFloat = CGFloat(progress) * height * 0.2
            steam.addLine(to: CGPoint(x: x + wave, y: mug.minY - 1 - rise))
        }
        context.stroke(steam, with: .color(ink.opacity(0.65)),
                       style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - The newer poses

/// Three dots over the head, counting up and starting again: thinking.
func drawThoughtDots(in context: inout GraphicsContext, size: CGSize, time: TimeInterval, ink: Color) {
    let width = size.width, height = size.height
    let shown = Int(time * 2.2) % 4
    let radius = max(0.9, width * 0.045)
    for index in 0..<3 {
        let lit = index < shown
        let centre = CGPoint(x: width * (0.64 + 0.13 * CGFloat(index)), y: height * (0.12 - 0.03 * CGFloat(index)))
        let dot = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        context.fill(dot, with: .color(ink.opacity(lit ? 0.9 : 0.25)))
    }
}

/// Small gold four-point sparks winking round the mark while it thinks.
func drawGoldSparks(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
    let gold = Color(red: 0.96, green: 0.76, blue: 0.31)
    let spots: [(CGFloat, CGFloat, Double)] = [(0.14, 0.22, 0), (0.86, 0.52, 1.3), (0.2, 0.8, 2.4)]
    for (x, y, offset) in spots {
        let pulse = max(0, sin(time * 3 + offset))
        guard pulse > 0.05 else { continue }
        drawSpark(in: &context, at: CGPoint(x: size.width * x, y: size.height * y),
                  radius: size.width * 0.08 * CGFloat(pulse), colour: gold.opacity(pulse))
    }
}

/// A four-point sparkle, the shape both Gemini marks are made of.
func drawSpark(in context: inout GraphicsContext, at centre: CGPoint, radius: CGFloat, colour: Color) {
    var path = Path()
    let pinch = radius * 0.22
    path.move(to: CGPoint(x: centre.x, y: centre.y - radius))
    path.addQuadCurve(to: CGPoint(x: centre.x + radius, y: centre.y), control: CGPoint(x: centre.x + pinch, y: centre.y - pinch))
    path.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y + radius), control: CGPoint(x: centre.x + pinch, y: centre.y + pinch))
    path.addQuadCurve(to: CGPoint(x: centre.x - radius, y: centre.y), control: CGPoint(x: centre.x - pinch, y: centre.y + pinch))
    path.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y - radius), control: CGPoint(x: centre.x - pinch, y: centre.y - pinch))
    context.fill(path, with: .color(colour))
}

/// A question mark bobbing beside the head: a person's move.
func drawQuestionMark(in context: inout GraphicsContext, size: CGSize, time: TimeInterval, ink: Color) {
    let width = size.width, height = size.height
    let bob = CGFloat(sin(time * 4)) * height * 0.03
    let mark = Text("?").font(.system(size: max(7, width * 0.42), weight: .heavy, design: .rounded))
        .foregroundColor(ink)
    context.draw(mark, at: CGPoint(x: width * 0.86, y: height * 0.16 + bob))
}

/// Confetti thrown up and falling: a turn done.
func drawConfetti(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
    let colours: [Color] = [Color(red: 0.98, green: 0.74, blue: 0.02), Color(red: 0.99, green: 0.25, blue: 0.24),
                            Color(red: 0.0, green: 0.73, blue: 0.36), Color(red: 0.19, green: 0.53, blue: 1.0)]
    for index in 0..<6 {
        let phase = (time * 0.8 + Double(index) / 6).truncatingRemainder(dividingBy: 1)
        let x = size.width * (0.1 + 0.16 * CGFloat(index)) + CGFloat(sin(time * 3 + Double(index))) * size.width * 0.03
        let y = size.height * (0.02 + 0.3 * CGFloat(phase))
        let side = max(1, size.width * 0.06)
        let piece = Path(CGRect(x: x, y: y, width: side, height: side * 0.6))
        context.fill(piece, with: .color(colours[index % colours.count].opacity(1 - phase * 0.6)))
    }
}

/// A ball tossed in an arc over the head: idling, playing.
func drawPlayBall(in context: inout GraphicsContext, size: CGSize, time: TimeInterval, ink: Color) {
    let phase = (time * 0.9).truncatingRemainder(dividingBy: 2)
    let across = phase < 1 ? phase : 2 - phase
    let x = size.width * (0.15 + 0.7 * CGFloat(across))
    let y = size.height * (0.16 - 0.14 * CGFloat(sin(.pi * across)))
    let radius = max(1, size.width * 0.07)
    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                 with: .color(ink))
}

/// A cross badge in the corner and a wisp of smoke: the turn failed.
func drawErrorMark(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
    let width = size.width, height = size.height
    let red = Color(red: 0.92, green: 0.26, blue: 0.24)
    let centre = CGPoint(x: width * 0.82, y: height * 0.2)
    let radius = width * 0.14
    context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                 with: .color(red))
    var cross = Path()
    let arm = radius * 0.5
    cross.move(to: CGPoint(x: centre.x - arm, y: centre.y - arm)); cross.addLine(to: CGPoint(x: centre.x + arm, y: centre.y + arm))
    cross.move(to: CGPoint(x: centre.x + arm, y: centre.y - arm)); cross.addLine(to: CGPoint(x: centre.x - arm, y: centre.y + arm))
    context.stroke(cross, with: .color(.white), style: StrokeStyle(lineWidth: max(1, width * 0.04), lineCap: .round))
    let rise = (time * 0.5).truncatingRemainder(dividingBy: 1)
    let puff = width * (0.05 + 0.04 * CGFloat(rise))
    let at = CGPoint(x: width * 0.3, y: height * (0.18 - 0.14 * CGFloat(rise)))
    context.fill(Path(ellipseIn: CGRect(x: at.x - puff, y: at.y - puff, width: puff * 2, height: puff * 2)),
                 with: .color(Color(white: 0.55).opacity(0.6 * (1 - rise))))
}
