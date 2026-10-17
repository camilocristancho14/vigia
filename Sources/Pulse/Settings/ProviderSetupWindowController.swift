import AppKit
import SwiftUI

/// A regular window so closing the chooser leaves the menu bar usable.
@MainActor
final class ProviderSetupWindowController {
    private let window: NSWindow

    private let mode: ProviderSetupMode

    init(settings: AppSettings, providers: Set<Provider>, mode: ProviderSetupMode) {
        self.mode = mode
        let isInitial = mode == .initial
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        self.window = window
        window.isReleasedWhenClosed = false
        // Ready first, then the rest that was found, then by name.
        func rank(_ provider: Provider) -> Int {
            settings.readyProviders.contains(provider) ? 0 : settings.detectedProviders.contains(provider) ? 1 : 2
        }
        let ordered = providers.sorted {
            let left = rank($0)
            let right = rank($1)
            if left != right { return left < right }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        window.contentView = NSHostingView(rootView: ProviderSetupView(
            settings: settings, providers: ordered, mode: mode,
            finish: { [weak window] selected in
                guard !isInitial || !selected.isEmpty else { return }
                window?.close()
                settings.selectProviders(selected.intersection(providers))
            },
            dismiss: { [weak window] in window?.close() }
        ))
        refreshTitle()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }

    func refreshTitle() {
        window.title = mode == .addMore ? .localized("Add services") : .localized("Choose services to monitor")
    }
}
