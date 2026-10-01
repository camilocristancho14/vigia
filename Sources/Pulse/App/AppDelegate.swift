// Modified for Vigía from Pulse (Apache-2.0).
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Not private: the status-item menu reads the language from it so the
    /// menu rebuilds when the language changes.
    let settings = AppSettings.restored()
    /// Not private for the same reason: the status-item menu shows a newer
    /// version when there is one.
    let update = AppUpdate()
    private let placement = PanelPlacement.restored()
    /// Not private: the settings pane shows what the system says about
    /// permission, which is not the same as what the switches say.
    private(set) lazy var alerts = UsageAlerts(settings: settings)
    /// Not private for the same reason: the settings pane is the only place
    /// that can report a combination the window server refused.
    let shortcuts = GlobalShortcutMonitor()
    private lazy var store = UsageStore(settings: settings, alerts: alerts)
    /// Starts usage windows after they reset, for the providers switched on.
    private lazy var primer = WindowPrimer(store: store, settings: settings)
    /// Bumped on every redraw of the status item. A tracking closure re-arms
    /// only while it still holds the latest, so the chain started by each
    /// settings change replaces the one before instead of running beside it.
    private var menuBarGeneration = 0

    private var panelController: FloatingPanelController?
    private var statusItem: NSStatusItem?
    /// The demo menu is a window, not an `NSMenu`. Kept so it stays on screen
    /// until the capture script shoots.
    private var demoMenuPanel: NSPanel?
    private var settingsWindow: SettingsWindowController?
    private var providerSetupWindow: ProviderSetupWindowController?
    private var preparedClaude = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        if DemoMode.isActive { DemoMode.applyAppearance() }

        settings.onMenuBarIconChange = { [weak self] in
            self?.updateMenuBarItem()
        }

        // The required `Settings` scene is empty on purpose; if the system
        // ever opens it (it did on a first launch), the person is looking at
        // a blank window. Close it and open the real one in its place.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow, !(window is SettingsWindow),
                  window.identifier?.rawValue.contains("Settings") == true else { return }
            MainActor.assumeIsolated {
                window.close()
                self?.openRealSettings()
            }
        }

        // **Writing to a pipe whose far end has closed raises SIGPIPE, whose
        // default is to kill the process.** Pulse writes to one: the Codex
        // helper's standard input. So that helper exiting — crashing, being
        // killed with the terminal it was started from, the user quitting
        // Codex — took Pulse down with it, with nothing in the log but
        // "Terminated due to signal 13". Ignored here rather than in
        // `CodexAppServer` because it is a property of the whole process, and
        // because the failure it prevents is not local to the caller that
        // happened to trigger it. The write then returns an error, which
        // `CodexAppServer.write(_:to:)` reads as the helper being gone.
        signal(SIGPIPE, SIG_IGN)

        // Caches whose format changed are invalidated by renaming the file;
        // this takes the orphans away rather than leaving them on disk.
        PulseStorage.removeSupersededFiles()

        // A launch agent left over from a loose build has to be handed over
        // before anything reads the state, or both builds start at login.
        // Demo runs skip this: a screenshot session must not register a login item.
        if !DemoMode.isActive {
            LoginItem.adoptBundleIfNeeded()
            LoginItem.applyDefaultOnFirstRun()
            LoginItem.repairPathIfNeeded()
        }

        // Daily at most, and only from a bundle — see `AppUpdate`.
        update.checkIfDue()

        settings.onChange = { [weak self] in
            self?.settingsChanged()
        }

        // Same issue, from the other side: a combination that works with no
        // pointer involved. Both unset until somebody sets one.
        shortcuts.on(.openSettings) { [weak self] in self?.showSettings() }
        shortcuts.on(.togglePanel) { [weak self] in
            // Through the setting rather than `controller.toggle()`, so the
            // panel is in the state the switch in settings claims it is, and
            // stays that way across a launch.
            self?.settings.isPanelVisible.toggle()
        }
        shortcuts.apply(settings)
        shortcuts.onRegistrationChange = { [weak self] in
            self?.restoreMenuBarEntryPointIfNeeded()
        }

        // A stored shortcut is only an entry point after Carbon accepts it.
        // Repair an impossible combination before removing the status item,
        // including settings written by a previous build.
        restoreMenuBarEntryPointIfNeeded()
        updateMenuBarItem()

        if settings.needsProviderSelection {
            showProviderSelection(providers: Set(Provider.builtIn), isInitial: true)
        } else {
            startMonitoring()
            if !settings.suggestedProviders.isEmpty {
                showProviderSelection(providers: settings.suggestedProviders, isInitial: false)
            }
        }

        if DemoMode.isActive {
            presentDemo()
        }
    }

    /// Screenshot scenes. The panel and the menu are already in the state
    /// `DemoMode.prepareDefaults()` stored; this only opens the menu or the
    /// settings window and then tells the capture script it can shoot.
    private func presentDemo() {
        switch DemoMode.scene {
        case .menu:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.presentDemoMenu()
            }
        case .settings:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showSettingsGeneral()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    DemoMode.signalReady()
                }
            }
        case .collapsed, .expanded:
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                DemoMode.signalReady()
            }
        }
    }

    /// `performClick` and `NSMenu.popUp` both return without a menu on a
    /// background launch, and `screencapture` does not record a menu even
    /// when one is tracking. A borderless panel at menu level uses the same
    /// item views the status menu just built, so the shot shows that menu.
    private func presentDemoMenu() {
        NSApp.activate(ignoringOtherApps: true)
        guard let button = statusItem?.button, let menu = statusItem?.menu else {
            DemoMode.signalReady()
            return
        }
        // `update()` refreshes item state and does not call `menuNeedsUpdate`,
        // so the session rows never get built unless the delegate runs itself.
        menuNeedsUpdate(menu)
        button.highlight(true)
        let panel = makeDemoMenuPanel(menu: menu, under: button)
        demoMenuPanel = panel
        panel.orderFrontRegardless()
        let titles = menu.items.map { item -> String in
            if item.isSeparatorItem { return "-" }
            if item.view != nil { return "row" }
            return item.title
        }.joined(separator: " | ")
        let note = "items=\(menu.items.count) \(titles) frame=\(panel.frame.debugDescription)\n"
        try? note.write(toFile: "/tmp/vigia-menu-debug", atomically: true, encoding: .utf8)
        DispatchQueue.main.async {
            DemoMode.signalReady()
        }
    }

    private func makeDemoMenuPanel(menu: NSMenu, under button: NSStatusBarButton) -> NSPanel {
        let width: CGFloat = 340
        let rows = demoMenuRows(menu: menu, width: width)
        let padY: CGFloat = 6
        let height = padY * 2 + rows.reduce(CGFloat(0)) { $0 + $1.height }
        let origin = demoMenuOrigin(width: width, height: height, under: button)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.appearance = NSApp.appearance

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        // The desktop behind a screenshot is black. A behind-window blur would
        // sample that and the light-mode labels would disappear, so the menu
        // paints its own fill and the material only tints that fill.
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        container.layer?.backgroundColor = (dark
            ? NSColor(calibratedWhite: 0.15, alpha: 1)
            : NSColor(calibratedWhite: 0.96, alpha: 1)
        ).cgColor

        let effect = NSVisualEffectView(frame: container.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .menu
        effect.blendingMode = .withinWindow
        effect.state = .active
        container.addSubview(effect)

        var y = height - padY
        for row in rows {
            y -= row.height
            if let item = row.item, item.isSeparatorItem {
                let line = NSBox(frame: NSRect(x: 12, y: y + (row.height - 1) / 2, width: width - 24, height: 1))
                line.boxType = .separator
                container.addSubview(line)
            } else if let view = row.session {
                view.frame = NSRect(x: 0, y: y, width: width, height: row.height)
                container.addSubview(view)
            } else if let item = row.item {
                addDemoMenuTitle(item, rowY: y, rowHeight: row.height, width: width, to: container)
            }
        }

        panel.contentView = container
        return panel
    }

    private struct DemoMenuRow {
        let item: NSMenuItem?
        let session: NSView?
        let height: CGFloat
    }

    /// Session rows are built here, not taken from the menu. AppKit rewrites
    /// `NSMenuItem.view.frame` to the bottom of whatever superview it has.
    private func demoMenuRows(menu: NSMenu, width: CGFloat) -> [DemoMenuRow] {
        var rows: [DemoMenuRow] = []
        for view in VigiaMenuRows.makeRows(settings: settings, store: store, width: width) {
            rows.append(DemoMenuRow(item: nil, session: view, height: max(view.frame.height, 22)))
        }
        for item in menu.items where !item.isHidden && item.view == nil {
            if item.isSeparatorItem {
                rows.append(DemoMenuRow(item: item, session: nil, height: 9))
            } else {
                rows.append(DemoMenuRow(item: item, session: nil, height: 24))
            }
        }
        return rows
    }

    private func demoMenuOrigin(width: CGFloat, height: CGFloat, under button: NSStatusBarButton) -> NSPoint {
        let screen = button.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 800)
        let anchor: NSRect
        if let window = button.window {
            anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        } else {
            anchor = NSRect(x: visible.maxX - 40, y: visible.maxY, width: 22, height: 22)
        }
        var origin = NSPoint(x: anchor.maxX - width, y: anchor.minY - height - 2)
        let minX = visible.minX + 8
        let maxX = visible.maxX - width - 8
        if origin.x < minX { origin.x = minX }
        if origin.x > maxX { origin.x = maxX }
        if origin.y < visible.minY + 8 { origin.y = visible.minY + 8 }
        return origin
    }

    private func addDemoMenuTitle(
        _ item: NSMenuItem,
        rowY: CGFloat,
        rowHeight: CGFloat,
        width: CGFloat,
        to container: NSView
    ) {
        let keys = demoMenuKeyEquivalent(item)
        let shortcutWidth: CGFloat = keys.isEmpty ? 0 : 46
        if item.state == .on, let image = NSImage(named: NSImage.menuOnStateTemplateName) {
            let mark = NSImageView(frame: NSRect(x: 8, y: rowY + (rowHeight - 12) / 2, width: 12, height: 12))
            mark.image = image
            mark.contentTintColor = .labelColor
            container.addSubview(mark)
        }
        let title = NSTextField(labelWithString: item.title)
        title.font = .menuFont(ofSize: 0)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        let titleX: CGFloat = 18
        let titleWidth = max(40, width - titleX - 14 - shortcutWidth - (shortcutWidth > 0 ? 8 : 0))
        title.frame = NSRect(x: titleX, y: rowY + (rowHeight - 16) / 2, width: titleWidth, height: 16)
        container.addSubview(title)
        guard !keys.isEmpty else { return }
        let shortcut = NSTextField(labelWithString: keys)
        shortcut.font = .menuFont(ofSize: 0)
        shortcut.textColor = .secondaryLabelColor
        shortcut.alignment = .right
        shortcut.frame = NSRect(x: width - 14 - shortcutWidth, y: title.frame.minY, width: shortcutWidth, height: 16)
        container.addSubview(shortcut)
    }

    private func demoMenuKeyEquivalent(_ item: NSMenuItem) -> String {
        let key = item.keyEquivalent
        guard !key.isEmpty else { return "" }
        let mask = item.keyEquivalentModifierMask
        var prefix = ""
        if mask.contains(.control) { prefix += "⌃" }
        if mask.contains(.option) { prefix += "⌥" }
        if mask.contains(.shift) { prefix += "⇧" }
        if mask.contains(.command) { prefix += "⌘" }
        if key == "\u{1b}" { return prefix + "⎋" }
        if key.count == 1, let scalar = key.unicodeScalars.first, CharacterSet.letters.contains(scalar) {
            return prefix + key.uppercased()
        }
        return prefix + key
    }

    /// Settings, or the chooser while no service has been picked.
    private func openRealSettings() {
        if settings.needsProviderSelection {
            if let chooser = providerSetupWindow {
                chooser.show()
            } else {
                showProviderSelection(providers: Set(Provider.builtIn), isInitial: true)
            }
        } else {
            showSettings()
        }
    }

    private func showSettingsGeneral() {
        let window = settingsWindow ?? SettingsWindowController(
            store: store, settings: settings, placement: placement,
            update: update, alerts: alerts, shortcuts: shortcuts
        )
        settingsWindow = window
        window.showGeneral()
    }

    private func showProviderSelection(providers: Set<Provider>, isInitial: Bool) {
        let window = ProviderSetupWindowController(settings: settings, providers: providers, isInitial: isInitial)
        providerSetupWindow = window
        window.show()
    }

    private func settingsChanged() {
        restoreMenuBarEntryPointIfNeeded()
        settingsWindow?.refreshTitle()
        providerSetupWindow?.refreshTitle()
        guard !settings.needsProviderSelection else { return }
        if panelController == nil {
            // Enabling a service in Settings is also an initial choice.
            providerSetupWindow?.close()
            startMonitoring()
        } else {
            panelController?.settingsChanged()
            store.settingsChanged()
            prepareClaudeIfSelected()
        }
    }

    private func startMonitoring() {
        guard !settings.needsProviderSelection, panelController == nil else { return }
        alerts.start { [weak self] in self?.showSettings() }
        let controller = FloatingPanelController(store: store, settings: settings, placement: placement)
        panelController = controller
        controller.contextMenu = { [weak self] in self?.panelMenu() ?? NSMenu() }
        if settings.isPanelVisible { controller.show() }
        store.start()
        if !DemoMode.isActive {
            primer.start()
            prepareClaudeIfSelected()
        }
    }

    private func prepareClaudeIfSelected() {
        if DemoMode.isActive { return }
        let claude = AccountKey(.claudeCode)
        guard settings.isEnabled(claude), !preparedClaude else { return }
        preparedClaude = true
        // Let the selection window close before either system prompt appears.
        Task { [weak self] in
            guard let self else { return }
            guard self.settings.isEnabled(claude) else {
                self.preparedClaude = false
                return
            }
            StatusLineHook.repairPathIfNeeded()
            ClaudeDesktopSession.requestPermissionAtLaunch(
                willBeUsed: [.automatic, .desktopApp].contains(self.settings.source(for: claude))
            ) { [weak self] in
                guard let self, self.settings.isEnabled(claude) else { return }
                self.store.refresh(claude)
            }
            StatusLineHook.offerOnFirstRun(willBeUsed: self.settings.isEnabled(claude))
        }
    }

    func showSettings() {
        showSettings(link: nil)
    }

    /// The rail's own menu: the same three things the menu bar offers, because
    /// this exists for the Mac where that menu cannot be reached.
    ///
    /// Built on each click rather than kept, so an update found since the last
    /// one is on it — an `NSMenu` held as a property would still be showing
    /// whatever was true when it was made.
    private func panelMenu() -> NSMenu {
        makeMenu()
    }

    private func updateMenuBarItem() {
        restoreMenuBarEntryPointIfNeeded()
        if settings.hidesMenuBarIcon {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = makeMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
        showMenuBarReading()
    }

    /// The menu bar item's face: Pulse's mark alone, or — with
    /// `showsUsageInMenuBar` on — the mark of the account whose ring is
    /// fullest and that ring's percentage, red past the warning line.
    ///
    /// Re-read whenever anything it reads changes: the tracking is armed
    /// again on every change, because `withObservationTracking` fires once.
    private func showMenuBarReading() {
        guard let item = statusItem else { return }
        menuBarGeneration += 1
        let generation = menuBarGeneration
        let (reading, remaining, style, label, accounts) = withObservationTracking {
            let reading = settings.showsUsageInMenuBar
                ? MenuBarReading.choose(
                    among: settings.shownAccounts,
                    chosen: settings.menuBarAccount.flatMap(AccountKey.init(id:)),
                    usage: store.usage(for:),
                    pinned: settings.pinnedWindow(for:),
                    warningAt: settings.warningThreshold.fraction
                )
                : nil
            // The label inside too: renaming the account is a change to show.
            // Who is mid-turn is read here too: a turn starting or ending has
            // to redraw the item, and nothing else about it changes.
            return (reading, settings.showsRemaining, settings.menuBarStyle,
                    reading.map { settings.label(for: $0.account) },
                    VigiaStatusFace.accounts(settings: settings, store: store))
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.menuBarGeneration == generation else { return }
                self.showMenuBarReading()
            }
        }

        VigiaStatusFace.draw(
            reading: reading,
            remaining: remaining,
            style: style,
            label: label,
            accounts: accounts,
            settings: settings,
            store: store,
            on: item
        )
    }

    /// An accessory app has no Dock icon. When the panel is also hidden, a
    /// successfully registered global shortcut is the only replacement for
    /// the status item; a stored shortcut that Carbon refused does not count.
    /// Internal and pure so the launch-safety rule can be pinned by a test.
    nonisolated static func menuBarIconMustRemainVisible(
        panelVisible: Bool,
        hasRegisteredShortcut: Bool
    ) -> Bool {
        !panelVisible && !hasRegisteredShortcut
    }

    private func restoreMenuBarEntryPointIfNeeded() {
        guard settings.hidesMenuBarIcon,
              Self.menuBarIconMustRemainVisible(
                  // Before a provider is selected there is no panel controller,
                  // whatever the persisted visibility preference says.
                  panelVisible: !settings.needsProviderSelection && settings.isPanelVisible,
                  hasRegisteredShortcut: shortcuts.hasRegisteredEntryPoint
              )
        else { return }
        settings.hidesMenuBarIcon = false
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusItem?.menu, let statusItem { VigiaStatusFace.menuWillOpen(item: statusItem) }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusItem?.menu, let statusItem else { return }
        VigiaStatusFace.menuDidClose(item: statusItem)
        // Anything that changed while the item was frozen.
        showMenuBarReading()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Only the menu bar's menu: the rail's own menu opens beside the rings
        // it would be repeating. Agent rows stay off any other menu so the
        // structural menu test still sees the original items.
        if menu === statusItem?.menu {
            menu.minimumWidth = DetailCardLayout.width + 12
            addAgentRows(to: menu)
        }
        populateMenu(menu)
    }

    /// claude-status-bar session rows for the accounts on the rail.
    private func addAgentRows(to menu: NSMenu) {
        guard !settings.needsProviderSelection, !settings.shownAccounts.isEmpty else { return }
        VigiaMenuRows.add(to: menu, settings: settings, store: store)
        menu.addItem(.separator())
    }

    @objc private func togglePanelFromMenu() {
        settings.isPanelVisible.toggle()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populateMenu(menu)
        return menu
    }

    private func populateMenu(_ menu: NSMenu) {
        // With no service chosen there is no rail, and nothing else on screen
        // says why. Rebuilt on every open, so it goes once a choice is made.
        if settings.needsProviderSelection {
            let item = NSMenuItem(
                title: .localized("Choose services to start monitoring…"),
                action: #selector(chooseServices),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if let newer = update.newer {
            let item = NSMenuItem(
                title: .localized("Pulse \(newer.version) is available"),
                action: #selector(checkForUpdate),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        // Some people want the menu bar and nothing at the screen's edge. The
        // switch lives in Settings → Position too; here it is one click from
        // where such a person already is. Through the setting, like the
        // shortcut, so a hidden panel stays hidden across a launch and hiding
        // the last way back brings the menu bar icon back (`settingsChanged`).
        if !settings.needsProviderSelection {
            let panelItem = NSMenuItem(
                title: .localized("Show floating panel"),
                action: #selector(togglePanelFromMenu),
                keyEquivalent: ""
            )
            panelItem.target = self
            panelItem.state = settings.isPanelVisible ? .on : .off
            menu.addItem(panelItem)
        }

        let settingsItem = NSMenuItem(
            title: .localized("Settings…"),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: .localized("Quit Pulse"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc private func chooseServices() {
        providerSetupWindow?.close()
        showProviderSelection(providers: Set(Provider.builtIn), isInitial: true)
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func checkForUpdate() {
        update.check()
    }

    /// Opening Pulse while it is already running — a double-click in
    /// Applications, Spotlight, Launchpad — opens Settings.
    ///
    /// An accessory app has no Dock icon, and with the panel and the menu bar
    /// icon both hidden (allowed once a global shortcut is registered) nothing
    /// of it is on screen. A forgotten shortcut then left no way back short
    /// of Activity Monitor; opening the app again is the way everybody tries
    /// first, and it did nothing at all.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Before a service is chosen the chooser is the way in, not Settings —
        // the one already open brought forward rather than a second made.
        openRealSettings()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let link = PulseLink(url: url) { showSettings(link: link) }
        }
    }

    private func showSettings(link: PulseLink?) {
        let window = settingsWindow ?? SettingsWindowController(store: store, settings: settings, placement: placement, update: update, alerts: alerts, shortcuts: shortcuts)
        settingsWindow = window
        window.show(link: link)
    }
}
