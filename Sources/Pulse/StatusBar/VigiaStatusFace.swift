// Modified for Vigía from Pulse (Apache-2.0).
// Menu bar face: the mascot of every AI on the rail, drawn by the same views
// as the notch and in the notch's order, moving only while that AI works, with
// what it is doing and for how long beside it — as claude-status-bar shows it.
// With none to show, Pulse's usage reading.
import AppKit
import SwiftUI

@MainActor
enum VigiaStatusFace {
    private static var host: MascotHostingView?
    /// While the item's menu is tracking, nothing on the item may change: a
    /// live view redrawing under an open menu makes the menu flicker, and a
    /// change of width moves it.
    private(set) static var menuIsOpen = false

    /// The accounts to draw, in the order of the rail. Called inside the
    /// observation closure: switching one off, or a turn starting under
    /// "working only", changes whether there is anything to draw.
    static func accounts(settings: AppSettings, store: UsageStore) -> [AccountKey] {
        guard settings.menuBarMascots else { return [] }
        var seen = Set<Provider>()
        return settings.shownAccounts.filter { account in
            guard !settings.menuBarHiddenAccounts.contains(account.id),
                  seen.insert(account.provider).inserted else { return false }
            return !settings.menuBarWorkingOnly || store.isRunning(account.provider)
        }
    }

    static func draw(
        reading: MenuBarReading?,
        remaining: Bool,
        style: MenuBarStyle,
        label: String?,
        accounts: [AccountKey],
        settings: AppSettings,
        store: UsageStore,
        on item: NSStatusItem
    ) {
        guard let button = item.button, !menuIsOpen else { return }

        guard !accounts.isEmpty else {
            host?.isHidden = true
            item.length = NSStatusItem.variableLength
            MenuBarReading.draw(reading, remaining: remaining, style: style, label: label, on: button)
            return
        }

        let host = host(for: button, item: item, settings: settings, store: store)
        if !host.isHidden { return }
        // Handing the button over: nothing of its own is left on it.
        button.image = nil
        button.attributedTitle = NSAttributedString()
        button.imagePosition = .noImage
        button.toolTip = "Vigía"
        host.isHidden = false
        host.sizeItem()
    }

    /// The menu is about to open: the live mascots give way to a photograph of
    /// themselves, so the item holds perfectly still until it closes.
    static func menuWillOpen(item: NSStatusItem) {
        menuIsOpen = true
        guard let host, !host.isHidden, let button = item.button,
              let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let snapshot = NSImage(size: host.bounds.size)
        snapshot.addRepresentation(rep)
        button.image = snapshot
        button.imagePosition = .imageOnly
        host.isHidden = true
    }

    /// Back to the live mascots, and to whatever changed while it was open.
    static func menuDidClose(item: NSStatusItem) {
        menuIsOpen = false
        guard let host, let button = item.button else { return }
        if button.imagePosition == .imageOnly, host.isHidden, button.image != nil {
            button.image = nil
            button.imagePosition = .noImage
            host.isHidden = false
            host.sizeItem()
        }
    }

    private static func host(
        for button: NSStatusBarButton, item: NSStatusItem, settings: AppSettings, store: UsageStore
    ) -> MascotHostingView {
        if let host, host.superview === button { return host }
        host?.removeFromSuperview()
        let host = MascotHostingView(rootView: MenuBarMascotsView(settings: settings, store: store))
        host.item = item
        host.translatesAutoresizingMaskIntoConstraints = false
        host.isHidden = true
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: MascotHostingView.inset),
            host.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        self.host = host
        return host
    }
}

/// Lets the SwiftUI row decide how wide the status item is, and lets every
/// click through to the button underneath, which opens the menu.
final class MascotHostingView: NSHostingView<MenuBarMascotsView> {
    static let inset: CGFloat = 4
    weak var item: NSStatusItem?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.sizeItem() }
    }

    func sizeItem() {
        guard !isHidden, !VigiaStatusFace.menuIsOpen, let item else { return }
        let width = ceil(fittingSize.width) + Self.inset * 2
        if abs(item.length - width) > 0.5 { item.length = width }
    }
}

struct MenuBarMascotsView: View {
    let settings: AppSettings
    let store: UsageStore

    var body: some View {
        let accounts = VigiaStatusFace.accounts(settings: settings, store: store)
        // Dealt over the whole rail, as the notch does, so each AI wears the
        // same colour and character in both places.
        let rail = settings.shownAccounts
        let tints = rail.contains(where: { settings.showsBotMark(for: $0) })
            ? BotMarkTint.deal(over: rail.map(\.provider), chosen: rail.map { settings.botColour(for: $0) })
            : []
        HStack(spacing: 10) {
            ForEach(accounts) { account in
                let index = rail.firstIndex(of: account) ?? 0
                MenuBarMascotItem(
                    account: account,
                    tint: index < tints.count ? tints[index] : .clear,
                    persona: settings.botPersona(for: account) ?? BotMarkPersona.automatic(at: index),
                    settings: settings,
                    store: store
                )
            }
        }
        .fixedSize()
        .frame(height: 22)
    }
}

private struct MenuBarMascotItem: View {
    let account: AccountKey
    let tint: Color
    let persona: BotMarkPersona
    let settings: AppSettings
    let store: UsageStore

    private static let markSize: CGFloat = 20

    var body: some View {
        let provider = account.provider
        let usage = store.usage(for: account)
        let headline = usage.headlineWindow(preferring: settings.pinnedWindow(for: account))
        let working = store.isRunning(provider)
        let pose = store.mascotPose(provider, usedFraction: UsageTint.isSpent(headline) ? 1 : headline?.usedFraction)

        HStack(spacing: 4) {
            mark(working: working, pose: pose, headline: headline)
                .frame(width: Self.markSize, height: Self.markSize)
            if working, settings.menuBarActivityText || settings.menuBarTimer {
                activity(for: provider)
            }
            if settings.menuBarPercent, let headline {
                Text(headline.percentText(remaining: settings.showsRemaining))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(UsageTint.isSpent(headline) ? Color.pulseExhausted : .primary)
            }
        }
        // Idle ones stay on screen, quieter, so the whole rail is always there.
        .opacity(working || settings.showsBotMark(for: account) ? 1 : 0.6)
        .animation(.easeOut(duration: 0.2), value: working)
    }

    @ViewBuilder
    private func mark(working: Bool, pose: MascotPose, headline: UsageWindow?) -> some View {
        let provider = account.provider
        if settings.showsBotMark(for: account), provider == .claudeCode {
            ClawdMarkView(pose: pose, colour: settings.menuBarColorMascots, size: Self.markSize)
        } else if settings.showsBotMark(for: account) {
            let body = tint == .clear ? BotMarkTint.body(for: provider) : tint
            BotMarkView(
                mood: BotMarkMood.resolve(
                    isBusy: working,
                    isRefreshing: store.isRefreshing(account),
                    isSpent: UsageTint.isSpent(headline) || (headline?.usedFraction ?? 0) >= 1,
                    hasReading: headline != nil
                ),
                persona: persona,
                bodyShape: settings.botBody(for: account),
                event: store.justFinishedWorking(provider) ? .workFinished : nil,
                pose: pose,
                activityLabel: store.activityLabel(provider),
                tint: body,
                eyeTint: BotMarkTint.eyes(on: body),
                size: Self.markSize
            )
        } else {
            LogoMascotView(provider: provider, pose: pose, size: Self.markSize)
        }
    }

    private func activity(for provider: Provider) -> some View {
        HStack(spacing: 4) {
            if settings.menuBarActivityText {
                Text(String.localized(String.LocalizationValue(store.activityLabel(provider) ?? "Thinking…")))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            if settings.menuBarTimer, let since = store.workingSince(provider) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(since)))
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
