// Modified for Vigía from Pulse (Apache-2.0).
// Session rows on the status-item menu, laid out like claude-status-bar.
import AppKit

@MainActor
enum VigiaMenuRows {
    static func add(to menu: NSMenu, settings: AppSettings, store: UsageStore) {
        for row in makeRows(settings: settings, store: store) {
            let item = NSMenuItem()
            item.view = row
            menu.addItem(item)
        }
    }

    /// Fresh rows, not yet installed in a menu. A menu item keeps moving its
    /// view, so the screenshot panel has to host copies of its own.
    static func makeRows(settings: AppSettings, store: UsageStore, width: CGFloat = 340) -> [SessionRowView] {
        settings.shownAccounts.map { account in
            let row = SessionRowView(id: account.id, width: width)
            let working = store.isRunning(account.provider)
            let usage = store.usage(for: account)
            let percent = usage.windows.first.map { window in
                "\(Int((min(max(window.usedFraction, 0), 1) * 100).rounded()))%"
            }
            let pill = working ? String.localized("ACTIVE") : String.localized("IDLE")
            row.configure(
                icon: icon(for: account, working: working, settings: settings),
                iconTint: working ? .labelColor : .tertiaryLabelColor,
                spinning: false,
                name: account.provider.displayName,
                branch: usage.plan ?? "",
                timer: percent,
                pillNormal: pillImage(pill),
                pillSelected: pillImage(pill, selected: true),
                pillInset: 12,
                timerGap: 10
            )
            return row
        }
    }

    private static func icon(for account: AccountKey, working: Bool, settings: AppSettings) -> NSImage? {
        if account.provider == .claudeCode, settings.showsBotMark(for: account) {
            let frames = ClawdFrames.images
            guard !frames.isEmpty else { return nil }
            let image = (working ? frames[frames.count / 2] : frames[0]).copy() as? NSImage
            image?.size = NSSize(width: 22, height: 16)
            return image
        }
        if account.provider == .grok, settings.showsBotMark(for: account) {
            return VigiaStatusFace.ballImage(pupilShift: working ? 1.5 : 0, points: 16)
        }
        return MenuBarReading.markImage(for: account.provider, size: 16)
    }

    /// The CLI/APP pill from claude-status-bar, used here for the working state.
    private static func pillImage(_ text: String, selected: Bool = false) -> NSImage {
        let drawn = text as NSString
        let font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        let pad: CGFloat = 7
        let height: CGFloat = 15
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let background = selected
            ? NSColor.white.withAlphaComponent(0.22)
            : (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.14 : 0.10)
        let foreground = selected ? NSColor.white : NSColor.labelColor
        let width = ceil(drawn.size(withAttributes: [.font: font]).width) + pad * 2
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            background.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
            let textSize = drawn.size(withAttributes: attributes)
            drawn.draw(
                at: NSPoint(
                    x: (rect.width - textSize.width) / 2,
                    y: (rect.height - textSize.height) / 2 - 1
                ),
                withAttributes: attributes
            )
            return true
        }
    }
}
