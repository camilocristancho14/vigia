import AppKit
import SwiftUI

/// What a first launch says after it switched on everything that was ready.
///
/// **Why this replaced the chooser on a first launch.** The chooser asked a new
/// person to read forty rows and tick the three tools they already use, then
/// answer a Keychain prompt and an alert about Claude Code's status line — five
/// steps before the first ring. When those tools are signed in, every one of
/// those steps has an obvious answer, so the first launch answers them and this
/// window says what it did: what is being watched, what is installed but needs
/// a sign-in first (with the one step that fixes it), and the status line
/// question as a checkbox rather than a modal alert. Nothing here is required;
/// closing it keeps what was switched on and connects nothing.
@MainActor
final class WelcomeWindowController {
    private let window: NSWindow

    init(
        settings: AppSettings,
        enabled: [Provider],
        needsSignIn: [Provider],
        offersStatusLine: Bool,
        addMore: @escaping () -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        self.window = window
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: WelcomeView(
            settings: settings,
            enabled: enabled,
            needsSignIn: needsSignIn,
            offersStatusLine: offersStatusLine,
            addMore: { [weak window] in
                window?.close()
                addMore()
            },
            done: { [weak window] connectStatusLine in
                window?.close()
                if connectStatusLine { Self.connectStatusLine() }
            }
        ))
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        refreshTitle()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }

    func refreshTitle() {
        window.title = .localized("Vigía is ready")
    }

    /// The same install, and the same account of a refusal, as the alert this
    /// checkbox stands in for (`StatusLineHook.offerOnFirstRun`).
    private static func connectStatusLine() {
        guard !StatusLineHook.install() else { return }
        let failed = NSAlert()
        failed.messageText = .localized("Couldn't connect the status line")
        failed.informativeText = .localized("~/.claude/settings.json couldn't be read, and Pulse won't overwrite a file it doesn't understand. Check it, then connect from Settings.")
        failed.runModal()
    }
}

struct WelcomeView: View {
    let settings: AppSettings
    let enabled: [Provider]
    let needsSignIn: [Provider]
    let offersStatusLine: Bool
    let addMore: () -> Void
    let done: (_ connectStatusLine: Bool) -> Void
    /// On by default: the question only appears for someone with Claude Code,
    /// for whom the status line is what keeps its ring reading after the
    /// login lapses. Unticking it is the "Not now" of the alert it replaces.
    @State private var connectStatusLine = true
    /// What the last remedy pressed on a row did, under that row.
    @State private var messages: [Provider: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(localized: "Vigía is ready")
                    .font(.title2.weight(.semibold))
                Text(localized: "These services were already signed in on this Mac, so Vigía is monitoring them now. You can change this anytime in Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(localized: "Monitoring now")
                        .font(.headline)
                        .padding(.bottom, 4)
                    ForEach(enabled) { provider in
                        HStack(spacing: 12) {
                            LobeIconView(provider: provider, size: 20)
                                .accessibilityHidden(true)
                            Text(provider.displayName).fontWeight(.medium)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }

                    if !needsSignIn.isEmpty {
                        Text(localized: "Installed — sign in to add")
                            .font(.headline)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                        ForEach(needsSignIn) { provider in
                            signInRow(provider)
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)

            if offersStatusLine {
                Toggle(isOn: $connectStatusLine) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localized: "Connect Claude Code's status line")
                        Text(localized: "Keeps Claude Code's usage readable after its login expires. This edits ~/.claude/settings.json; you can disconnect it in Settings.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                Button(String.localized("Add more services…"), action: addMore)
                Spacer()
                Button(String.localized("Done")) { done(offersStatusLine && connectStatusLine) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .id(settings.language)
    }

    @ViewBuilder
    private func signInRow(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                LobeIconView(provider: provider, size: 20)
                    .accessibilityHidden(true)
                Text(provider.displayName).fontWeight(.medium)
                Spacer()
                if let remedy = ConnectionRemedy.forSetup(of: provider) {
                    Button(remedy.title) { perform(remedy, for: provider) }
                        .controlSize(.small)
                }
            }
            if let message = messages[provider] {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }

    /// The three remedies `ConnectionRemedy.forSetup` gives a primary account,
    /// done the way the settings pane does them. Anything else is not a step
    /// this window can take, so it opens the setup page instead.
    private func perform(_ remedy: ConnectionRemedy, for provider: Provider) {
        messages[provider] = nil
        switch remedy {
        case .copyCommand(let command):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            messages[provider] = String.localized("Copied — run \(command) in your terminal to sign in.")
        case .openApp(let name):
            let candidates = [
                URL.applicationDirectory.appending(path: "\(name).app"),
                URL.homeDirectory.appending(path: "Applications/\(name).app"),
            ]
            guard let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                messages[provider] = String.localized("Couldn't find \(name). Open setup help.")
                return
            }
            Task {
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: app, configuration: .init())
                } catch {
                    messages[provider] = String.localized("Couldn't open \(name). Open setup help.")
                }
            }
        default:
            NSWorkspace.shared.open(ConnectionRemedy.helpURL(for: provider))
        }
    }
}
