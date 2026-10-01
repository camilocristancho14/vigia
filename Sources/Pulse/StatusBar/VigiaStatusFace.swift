// Modified for Vigía from Pulse (Apache-2.0).
// Menu bar face: the mascot of every AI on the rail (Clawd, the Grok ball, the
// others' marks), moving only while that AI works, with what it is doing and
// for how long beside it — as claude-status-bar shows it. With none to show,
// Pulse's usage reading. Animation matches claude-status-bar's sprite rate.
import AppKit

@MainActor
enum VigiaStatusFace {
    /// One AI in the menu bar: its mascot, moving while it works.
    struct Mascot: Equatable {
        let provider: Provider
        let working: Bool
        /// English key for `String.localized`; nil while idle.
        let label: String?
        let since: Date?
    }

    private static let maxMascots = 6
    private static let height: CGFloat = 18
    private static let gap: CGFloat = 6
    private static let textFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let timerFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    private static var timer: Timer?
    private static var tick = 0
    private static weak var button: NSStatusBarButton?
    private static var mascots: [Mascot] = []
    /// Painting into the button while its menu is tracking makes the open menu
    /// flicker, so nothing is touched until it closes.
    private static var menuIsOpen = false
    private static var laidOutAsReading = true

    /// Every shown account's AI, working ones first, so what is happening is
    /// always on screen. Called inside the observation closure: a turn
    /// starting, ending or changing what it does redraws the item.
    static func mascots(settings: AppSettings, store: UsageStore) -> [Mascot] {
        var seen = Set<Provider>()
        var found: [Mascot] = []
        for account in settings.shownAccounts where seen.insert(account.provider).inserted {
            let provider = account.provider
            let working = store.isRunning(provider)
            found.append(Mascot(
                provider: provider,
                working: working,
                label: working ? (store.activityLabel(provider) ?? "Thinking…") : nil,
                since: working ? store.workingSince(provider) : nil
            ))
        }
        return Array(found.sorted { $0.working && !$1.working }.prefix(maxMascots))
    }

    static func draw(
        reading: MenuBarReading?,
        remaining: Bool,
        style: MenuBarStyle,
        label: String?,
        mascots: [Mascot],
        on button: NSStatusBarButton
    ) {
        self.button = button
        self.mascots = mascots

        guard !mascots.isEmpty else {
            stopTimer()
            laidOutAsReading = true
            MenuBarReading.draw(reading, remaining: remaining, style: style, label: label, on: button)
            return
        }

        if laidOutAsReading {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString()
            button.toolTip = "Vigía"
            laidOutAsReading = false
        }
        guard !menuIsOpen else { return }
        paintMascots(on: button)
        syncTimer()
    }

    /// The status item's menu opened or closed. Frozen while open, repainted
    /// with whatever changed in the meantime when it closes.
    static func setMenuOpen(_ open: Bool) {
        menuIsOpen = open
        if open {
            stopTimer()
        } else if let button, !mascots.isEmpty {
            paintMascots(on: button)
            syncTimer()
        }
    }

    private static func syncTimer() {
        guard mascots.contains(where: \.working) else { return stopTimer() }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 12.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                tick += 1
                guard let button = self.button else { return }
                paintMascots(on: button)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Layout

    /// The status word's width as drawn, capped so one chatty tool name cannot
    /// push the other marks off the menu bar.
    private static func labelWidth(of mascot: Mascot) -> CGFloat {
        let text = String.localized(String.LocalizationValue(mascot.label ?? "Thinking…"))
        return min(ceil((text as NSString).size(withAttributes: [.font: textFont]).width), 120)
    }

    private static let timerWidth: CGFloat =
        ceil(("00:00" as NSString).size(withAttributes: [.font: timerFont]).width)

    private static func iconWidth(of mascot: Mascot) -> CGFloat {
        mascot.provider == .claudeCode ? 22 : height
    }

    private static func width(of mascot: Mascot) -> CGFloat {
        guard mascot.working else { return iconWidth(of: mascot) }
        return iconWidth(of: mascot) + 4 + labelWidth(of: mascot) + 4 + timerWidth
    }

    private static func paintMascots(on button: NSStatusBarButton) {
        let items = mascots
        let widths = items.map(width(of:))
        let total = widths.reduce(0, +) + gap * CGFloat(max(0, items.count - 1))
        let size = NSSize(width: total, height: height)
        let tick = tick
        let now = Date()

        // Drawn per tick under the button's own appearance, so the marks come
        // out light on a dark menu bar and dark on a light one.
        var image = NSImage(size: size)
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            let ink = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .white
            image = NSImage(size: size, flipped: false) { _ in
                var x: CGFloat = 0
                for (mascot, width) in zip(items, widths) {
                    let icon = iconWidth(of: mascot)
                    draw(mascot, tick: tick, in: NSRect(x: x, y: 0, width: icon, height: height), ink: ink)
                    if mascot.working {
                        drawStatus(mascot, at: x + icon + 4, now: now, ink: ink)
                    }
                    x += width + gap
                }
                return true
            }
        }
        image.isTemplate = false
        button.image = image
    }

    private static func drawStatus(_ mascot: Mascot, at x: CGFloat, now: Date, ink: NSColor) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let text = String.localized(String.LocalizationValue(mascot.label ?? "Thinking…"))
        let labelWidth = labelWidth(of: mascot)
        let textHeight = ceil(textFont.boundingRectForFont.height)
        let y = (height - textHeight) / 2
        (text as NSString).draw(
            in: NSRect(x: x, y: y, width: labelWidth, height: textHeight),
            withAttributes: [.font: textFont, .foregroundColor: ink, .paragraphStyle: style]
        )
        let elapsed = max(0, Int(now.timeIntervalSince(mascot.since ?? now)))
        let clock = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        let right = NSMutableParagraphStyle()
        right.alignment = .right
        (clock as NSString).draw(
            in: NSRect(x: x + labelWidth + 4, y: y, width: timerWidth, height: textHeight),
            withAttributes: [.font: timerFont, .foregroundColor: ink.withAlphaComponent(0.7), .paragraphStyle: right]
        )
    }

    private static func draw(_ mascot: Mascot, tick: Int, in rect: NSRect, ink: NSColor) {
        let phase = Double(tick) / 2.0
        switch mascot.provider {
        case .claudeCode:
            let frames = ClawdFrames.images
            guard !frames.isEmpty else { return }
            let frame = frames[mascot.working ? tick % frames.count : 0]
            frame.draw(in: NSRect(x: rect.minX, y: rect.midY - 8, width: 22, height: 16))
        case .grok:
            let shift = mascot.working ? CGFloat(sin(phase)) * 2 : 0
            tint(ballImage(pupilShift: shift), in: rect, ink: ink, alpha: 1)
        default:
            guard let logo = LobeIconStore.image(for: mascot.provider) else { return }
            // Working: the logo bobs and breathes. Idle: still and dimmed.
            let bob = mascot.working ? CGFloat(sin(phase)) * 1.5 : 0
            let alpha = mascot.working ? 0.8 + 0.2 * CGFloat(sin(phase * 0.8)) : 0.5
            let box = rect.insetBy(dx: 1, dy: 1).offsetBy(dx: 0, dy: bob)
            tint(logo, in: box, ink: ink, alpha: alpha)
        }
    }

    /// A template image filled with the menu bar's ink.
    private static func tint(_ image: NSImage, in rect: NSRect, ink: NSColor, alpha: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(alpha)
        context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        image.draw(in: rect)
        ink.set()
        rect.fill(using: .sourceIn)
        context.endTransparencyLayer()
        context.restoreGState()
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
