// Modified for Vigía from Pulse (Apache-2.0).
// Session rows on the status-item menu, laid out like claude-status-bar.
import AppKit
import SwiftUI

@MainActor
enum VigiaMenuRows {
    /// One detail card per AI on the rail — the card the notch opens when the
    /// pointer rests on a ring, with the same figures, in place of a bare row.
    static func add(to menu: NSMenu, settings: AppSettings, store: UsageStore) {
        for card in makeCards(settings: settings, store: store) {
            let item = NSMenuItem()
            item.view = card
            menu.addItem(item)
        }
    }

    /// The cards, not yet installed in a menu: the screenshot panel hosts
    /// copies of its own, as it does for rows.
    static func makeCards(settings: AppSettings, store: UsageStore) -> [NSView] {
        settings.shownAccounts.map { account in
            let card = UsageDetailCard(
                usesGlass: false,
                usage: store.usage(for: account),
                title: settings.label(for: account),
                edge: .top,
                showsRemaining: settings.showsRemaining,
                showsForecast: settings.showsForecast,
                resetCredits: account == AccountKey(.codex) ? store.codexResetCredits : nil,
                isDetailed: settings.showsDetailedCard(for: account),
                pointerCenter: 0,
                showsPointer: false
            )
            .environment(\.usageWarningThreshold, settings.warningThreshold.fraction)
            // The card is drawn on solid black, as on the notch, and its text
            // is `.primary`: in a light menu that is black on black.
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)

            let host = NSHostingView(rootView: card)
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame.size = host.fittingSize
            return host
        }
    }

    /// Fresh rows, not yet installed in a menu. A menu item keeps moving its
    /// view, so the screenshot panel has to host copies of its own.
    static func makeRows(settings: AppSettings, store: UsageStore, width: CGFloat = 340) -> [SessionRowView] {
        // Dealt over the whole rail, as the notch and the menu bar do, so each
        // AI keeps its colour and character in all three places.
        let rail = settings.shownAccounts
        let tints = rail.contains(where: { settings.showsBotMark(for: $0) })
            ? BotMarkTint.deal(over: rail.map(\.provider), chosen: rail.map { settings.botColour(for: $0) })
            : []

        return rail.enumerated().map { index, account in
            let row = SessionRowView(id: account.id, width: width)
            let working = store.isRunning(account.provider)
            let usage = store.usage(for: account)
            // The same figure the notch's ring shows, not the first window.
            let headline = usage.headlineWindow(preferring: settings.pinnedWindow(for: account))
            let percent = headline?.percentText(remaining: settings.showsRemaining)
            let pill = working ? String.localized("ACTIVE") : String.localized("IDLE")
            let detail: String = if working {
                String.localized(String.LocalizationValue(store.activityLabel(account.provider) ?? "Thinking…"))
            } else {
                usage.plan ?? ""
            }
            let marked = settings.showsBotMark(for: account)
            row.configure(
                icon: icon(
                    for: account, working: working, marked: marked, headline: headline,
                    tint: index < tints.count ? tints[index] : .clear,
                    persona: settings.botPersona(for: account) ?? BotMarkPersona.automatic(at: index),
                    settings: settings, store: store
                ),
                iconTint: working || marked ? .labelColor : .tertiaryLabelColor,
                spinning: false,
                name: account.provider.displayName,
                branch: detail,
                timer: percent,
                pillNormal: pillImage(pill),
                pillSelected: pillImage(pill, selected: true),
                pillInset: 12,
                timerGap: 10
            )
            return row
        }
    }

    /// The same mark the notch draws, as a still: Clawd, the account's bot, or
    /// its logo.
    private static func icon(
        for account: AccountKey, working: Bool, marked: Bool, headline: UsageWindow?,
        tint: Color, persona: BotMarkPersona, settings: AppSettings, store: UsageStore
    ) -> NSImage? {
        guard marked else { return MenuBarReading.markImage(for: account.provider, size: 16) }
        if account.provider == .claudeCode {
            let frames = ClawdFrames.images
            guard !frames.isEmpty else { return nil }
            let image = (working ? frames[frames.count / 2] : frames[0]).copy() as? NSImage
            image?.size = NSSize(width: 22, height: 16)
            return image
        }

        let body = tint == .clear ? BotMarkTint.body(for: account.provider) : tint
        var programme = BotMarkProgramme.forMood(
            BotMarkMood.resolve(
                isBusy: working,
                isRefreshing: false,
                isSpent: UsageTint.isSpent(headline) || (headline?.usedFraction ?? 0) >= 1,
                hasReading: headline != nil
            ),
            persona: persona, isQuiet: false, isPointedAt: false, at: Date()
        )
        programme.shape = settings.botBody(for: account).shape
        programme.color = body
        programme.eyeColor = BotMarkTint.eyes(on: body)
        programme.viewWidth = 18
        let still = BotMarkView.still(for: programme)
        let renderer = ImageRenderer(content:
            Canvas(rendersAsynchronously: false) { context, size in
                drawBotMark(still.frame, config: still.config, in: &context, size: size)
            }
            .frame(width: 18, height: 18)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
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
