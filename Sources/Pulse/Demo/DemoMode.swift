// Modified for Vigía from Pulse (Apache-2.0).
// Demo data for screenshot runs. No network, no login item, no real sessions.
import AppKit
import Foundation

enum DemoMode {
    enum Scene: String {
        case collapsed
        case expanded
        case menu
        case settings
    }

    static var isActive: Bool {
        if ProcessInfo.processInfo.environment["VIGIA_DEMO"] == "1" { return true }
        return FileManager.default.fileExists(atPath: "/tmp/vigia-demo")
    }

    static var scene: Scene {
        let fromEnv = ProcessInfo.processInfo.environment["VIGIA_SCENE"]
        let fromFile = try? String(contentsOfFile: "/tmp/vigia-demo", encoding: .utf8)
        let raw = (fromEnv ?? fromFile ?? "expanded")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Scene(rawValue: raw) ?? .expanded
    }

    /// Writes the defaults `AppSettings.restored()` and `PanelPlacement.restored()`
    /// read, before either of them runs.
    static func prepareDefaults() {
        let defaults = UserDefaults.standard
        let scene = scene
        let showsPanel = scene == .collapsed || scene == .expanded
        defaults.set(showsPanel, forKey: "settings.panelVisible")
        defaults.set(false, forKey: "settings.hidesMenuBarIcon")
        defaults.set(scene != .expanded, forKey: "settings.autoCollapse")
        defaults.set(true, forKey: "settings.topRailShowsPercentages")
        defaults.set(AppLanguage.spanish.rawValue, forKey: "settings.language")
        defaults.set(
            ["claudeCode": true, "grokBot": true],
            forKey: "settings.botMarks"
        )
        defaults.set(
            ["claudeCode", "grokBot", "grok", "antigravity"],
            forKey: ProviderSelection.enabledKey
        )
        defaults.set(Provider.builtIn.map(\.rawValue), forKey: ProviderSelection.offeredKey)
        defaults.set(true, forKey: ProviderSelection.hasRunKey)
        defaults.set("top", forKey: "panel.edge")
        defaults.set(false, forKey: "panel.floating")
        defaults.set(0.5, forKey: "panel.horizontalRatio")
        defaults.set(0.0, forKey: "panel.verticalRatio")
    }

    static func readings(now: Date = Date()) -> [ProviderUsage] {
        [
            reading(.claudeCode, fraction: 0.58, plan: "Pro", now: now),
            reading(.grokBot, fraction: 1.0, plan: "SuperGrok", now: now),
            reading(.grok, fraction: 0.63, plan: "SuperGrok", now: now),
            reading(.antigravity, fraction: 0.0, plan: "Pro", now: now),
        ]
    }

    /// Claude Code is mid-turn, so the menu bar shows its status word and timer.
    static func runningProviders() -> Set<Provider> { [.claudeCode] }

    static func activityLabels() -> [Provider: String] { [.claudeCode: "Reading"] }

    /// Grok Bot finished a turn a couple of minutes ago and is on its break.
    static func finishedAt(now: Date = Date()) -> [Provider: Date] {
        [.grok: now.addingTimeInterval(-120)]
    }

    static func startedAt(now: Date = Date()) -> [Provider: Date] {
        [.claudeCode: now.addingTimeInterval(-74)]
    }

    static func signalReady() {
        try? Data("ready\n".utf8).write(to: URL(fileURLWithPath: "/tmp/vigia-ready"))
    }

    /// Forces the app's windows to the appearance the capture script asked for.
    /// The script also switches the system appearance so the menu bar matches.
    @MainActor
    static func applyAppearance() {
        let fromEnv = ProcessInfo.processInfo.environment["VIGIA_APPEARANCE"]
        let fromFile = try? String(contentsOfFile: "/tmp/vigia-appearance", encoding: .utf8)
        let raw = (fromEnv ?? fromFile ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch raw {
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            break
        }
    }

    private static func reading(
        _ provider: Provider,
        fraction: Double,
        plan: String,
        now: Date
    ) -> ProviderUsage {
        let window = UsageWindow(
            id: "5h",
            kind: .fiveHour,
            scope: nil,
            usedFraction: fraction,
            windowSeconds: 5 * 3600,
            resetsAt: now.addingTimeInterval(3600)
        )
        return ProviderUsage(
            account: AccountKey(provider),
            windows: [window],
            observedAt: now,
            state: .live,
            plan: plan,
            creditBalance: nil
        )
    }
}
