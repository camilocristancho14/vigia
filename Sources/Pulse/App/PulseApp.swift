// Modified for Vigía from Pulse (Apache-2.0).
import AppKit
import SwiftUI

/// The executable's entry point.
///
/// Claude Code runs this same binary as its status line command (see
/// `StatusLineHook`), so that case has to be settled before any of the app
/// starts: it must read stdin, print one line and exit rather than open a
/// window. Hence a separate entry type — `PulseApp` keeps the plain `main()`
/// that `App` provides.
@main
enum PulseMain {
    static func main() {
        if CommandLine.arguments.contains(StatusLineHook.modeArgument) {
            StatusLineHook.runAsStatusLine()
            exit(0)
        }

        // Registering has to run from this executable, since what gets written
        // into Claude Code's settings is this binary's own path.
        if CommandLine.arguments.contains("--install-statusline") {
            print(StatusLineHook.install() ? "installed" : "failed")
            exit(0)
        }
        if CommandLine.arguments.contains("--uninstall-statusline") {
            print(StatusLineHook.uninstall() ? "uninstalled" : "failed")
            exit(0)
        }

        // Before anything opens a file in Application Support: builds from
        // before the rename kept it in a folder called Pulse. Only renames,
        // and only when Vigia's folder isn't there yet. After the status line
        // branches, which never open that folder and run every few seconds.
        PulseStorage.migrateIfNeeded()

        // Before `LegacyDefaults.migrateIfNeeded()` deliberately: this command
        // reads settings and must not be the thing that migrates them. A
        // status line running it every couple of seconds is not the moment to
        // decide an installation's defaults — the app does that at launch.
        if CommandLine.arguments.contains(UsageReport.modeArgument) {
            exit(UsageReport.run())
        }

        // Before anything reads a setting: running from a bundle changes
        // which `UserDefaults` domain that means.
        LegacyDefaults.migrateIfNeeded()

        // Spanish by default on a real launch. Tests construct AppDelegate
        // directly and never reach here, so they keep the English bundle.
        if UserDefaults.standard.object(forKey: "settings.language") == nil {
            UserDefaults.standard.set(AppLanguage.spanish.rawValue, forKey: "settings.language")
        }
        if DemoMode.isActive {
            DemoMode.prepareDefaults()
        }

        // Every window Vigía shows is made on purpose by `AppDelegate`; none
        // is meant to come back by itself at launch because it was open at
        // quit. Registered, not set, so a person's own choice still wins.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])

        PulseApp.main()
    }
}

struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI needs one scene, and AppKit owns everything Vigía shows: the
        // status item (so it can be removed at runtime) and the real settings
        // window. So the scene is one that can never put anything on screen —
        // a menu bar extra that is never inserted.
        //
        // **Not `Settings { EmptyView() }`, which this was.** That is a window,
        // and macOS opened it on its own — on a first launch, and on any
        // launch that restored it — so the first thing a new person saw was a
        // blank white window titled "Vigía" that `AppDelegate` then closed and
        // replaced. A scene with no window cannot be opened by anybody.
        // `windowBecameKey` stays as the net under any window that still is.
        MenuBarExtra("Vigía", isInserted: .constant(false)) {
            EmptyView()
        }
        // The delegate owns the real settings window, and Command, opens it.
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(String.localized("Settings…")) {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
