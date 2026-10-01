// Modified for Vigía from Pulse (Apache-2.0).
// Menu bar face: Clawd or the Grok ball when that mascot is on, otherwise
// Pulse's usage reading. Animation matches claude-status-bar's sprite rate.
import AppKit

@MainActor
enum VigiaStatusFace {
    private static var timer: Timer?
    private static var tick = 0
    private static weak var button: NSStatusBarButton?
    private static var claudeWorking = false
    private static var grokWorking = false
    private static var kind: Kind = .reading

    private enum Kind {
        case clawd
        case ball
        case reading
    }

    static func draw(
        reading: MenuBarReading?,
        remaining: Bool,
        style: MenuBarStyle,
        label: String?,
        settings: AppSettings,
        store: UsageStore,
        on button: NSStatusBarButton
    ) {
        let claude = AccountKey(.claudeCode)
        let grok = AccountKey(.grok)
        let claudeMark = settings.isEnabled(claude) && settings.showsBotMark(for: claude)
        let grokMark = settings.isEnabled(grok) && settings.showsBotMark(for: grok)
        claudeWorking = store.isRunning(.claudeCode)
        grokWorking = store.isRunning(.grok)
        self.button = button

        if claudeWorking && claudeMark {
            kind = .clawd
        } else if grokWorking && grokMark {
            kind = .ball
        } else if claudeMark {
            kind = .clawd
        } else if grokMark {
            kind = .ball
        } else {
            kind = .reading
        }

        if kind == .reading {
            timer?.invalidate()
            timer = nil
            MenuBarReading.draw(reading, remaining: remaining, style: style, label: label, on: button)
            return
        }

        paintMascot(on: button)
        let animating = (kind == .clawd && claudeWorking) || (kind == .ball && grokWorking)
        if animating, timer == nil {
            let timer = Timer(timeInterval: 1.0 / 12.5, repeats: true) { _ in
                MainActor.assumeIsolated {
                    tick += 1
                    guard let button = self.button else { return }
                    paintMascot(on: button)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !animating {
            timer?.invalidate()
            timer = nil
        }
    }

    private static func paintMascot(on button: NSStatusBarButton) {
        switch kind {
        case .clawd:
            let frames = ClawdFrames.images
            guard !frames.isEmpty else { return }
            let index = claudeWorking ? tick % frames.count : 0
            let image = frames[index]
            image.size = NSSize(width: 22, height: 16)
            button.image = image
        case .ball:
            let shift = grokWorking ? CGFloat(sin(Double(tick) / 2.0)) * 2 : 0
            button.image = ballImage(pupilShift: shift)
        case .reading:
            return
        }
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString()
        button.toolTip = "Vigía"
    }

    /// Round template mark. Eyes are holes so the menu bar color shows through.
    static func ballImage(pupilShift: CGFloat, points: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: points, height: points), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            context.setBlendMode(.destinationOut)
            let eye = points * 0.16
            let y = rect.midY + points * 0.06
            for side in [-1.0, 1.0] as [CGFloat] {
                let origin = NSPoint(
                    x: rect.midX + side * points * 0.18 + pupilShift - eye / 2,
                    y: y - eye / 2
                )
                NSBezierPath(ovalIn: NSRect(origin: origin, size: NSSize(width: eye, height: eye))).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
