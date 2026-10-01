import SwiftUI

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
        let x = mug.minX + mug.width * (0.32 + 0.36 * Double(index))
        var steam = Path()
        steam.move(to: CGPoint(x: x, y: mug.minY - 1))
        for step in 1...6 {
            let progress = Double(step) / 6
            let wave = sin(time * 2.4 + progress * 4 + Double(index) * 1.7) * width * 0.025
            steam.addLine(to: CGPoint(x: x + wave, y: mug.minY - 1 - progress * height * 0.2))
        }
        context.stroke(steam, with: .color(ink.opacity(0.65)),
                       style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
    }
}
