import SwiftUI

/// What is drawn over the mark for the pose it is in, on top of the upstream
/// face: the cup, the laptop, the speed lines, the sweat, the stars and the
/// sleeper's Zs. The faces themselves are the upstream's states.
func drawMascotOverlay(pose: MascotPose, mood: BotMarkMood, in context: inout GraphicsContext,
                       size: CGSize, time: TimeInterval) {
    switch (pose, mood) {
    case (.coffee, .idle): drawCoffeeBreak(in: &context, size: size, time: time)
    case (.type, .working): drawLaptop(in: &context, size: size, time: time)
    case (.run, .working): drawSpeedLines(in: &context, size: size, time: time)
    case (.tired, .idle): drawSweat(in: &context, size: size, time: time)
    case (.spent, _): drawDizzyStars(in: &context, size: size, time: time)
    case (.sleep, .idle): drawSleepZs(in: &context, size: size, time: time)
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
