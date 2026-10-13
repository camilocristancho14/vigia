import AppKit
import SwiftUI
import Testing
@testable import Pulse

/// The status-item menu's cards: what colour a limit is in, what line of
/// warning it earns, and how fresh the header says the figures are.
@Suite("Menu usage card")
@MainActor
struct MenuUsageCardTests {
    private static let now = Date(timeIntervalSince1970: 1_791_000_000)

    private static func window(_ id: String, _ kind: UsageWindow.Kind, used: Double, seconds: Int,
                               resetsIn: TimeInterval, scope: String? = nil, label: String? = nil,
                               exhausted: Bool = false) -> UsageWindow {
        UsageWindow(id: id, kind: kind, scope: scope, usedFraction: used, windowSeconds: seconds,
                    resetsAt: now.addingTimeInterval(resetsIn), isExhausted: exhausted, label: label)
    }

    @Test("A spent limit is the exhausted colour and says it is used up until the reset")
    func spent() {
        let week = Self.window("w", .weekly, used: 1, seconds: 7 * 86_400, resetsIn: 20 * 3600, exhausted: true)
        let risk = MenuUsageCard.risk(of: week, warningAt: 0.75, forecast: true, now: Self.now)
        #expect(risk.colour == .pulseExhausted)
        #expect(risk.warning == String.localized("Used up until it resets"))
    }

    @Test("A low figure on course to run out is a risk; one that will last says nothing")
    func forecast() {
        // 14% used halfway through the window: fine.
        let calm = Self.window("a", .fiveHour, used: 0.14, seconds: 5 * 3600, resetsIn: 2.5 * 3600)
        let calmRisk = MenuUsageCard.risk(of: calm, warningAt: 0.75, forecast: true, now: Self.now)
        #expect(calmRisk.colour == .pulseGood && calmRisk.warning == nil)
        // 40% gone in the first half hour: it will not last.
        let racing = Self.window("b", .fiveHour, used: 0.4, seconds: 5 * 3600, resetsIn: 4.5 * 3600)
        let racingRisk = MenuUsageCard.risk(of: racing, warningAt: 0.75, forecast: true, now: Self.now)
        #expect(racingRisk.colour == .pulseWarning && racingRisk.warning != nil)
        // The forecast switched off: only the used share speaks.
        #expect(MenuUsageCard.risk(of: racing, warningAt: 0.75, forecast: false, now: Self.now).warning == nil)
    }

    @Test("Fresh figures say so in green; stale or old ones in amber")
    func freshness() throws {
        let account = AccountKey(.antigravity)
        let live = ProviderUsage(account: account, windows: [], observedAt: Self.now.addingTimeInterval(-120),
                                 state: .live, plan: nil, creditBalance: nil)
        let fresh = try #require(MenuUsageCard.freshness(of: live, now: Self.now))
        #expect(fresh.isFresh && fresh.colour == .pulseGood)
        let cached = ProviderUsage(account: account, windows: [], observedAt: Self.now.addingTimeInterval(-3 * 3600),
                                   state: .stale, plan: nil, creditBalance: nil)
        let old = try #require(MenuUsageCard.freshness(of: cached, now: Self.now))
        #expect(!old.isFresh && old.colour == .pulseCaution)
        #expect(old.text.hasPrefix(String.localized("Updated \("")").trimmingCharacters(in: .whitespaces)))
        let missing = ProviderUsage(account: account, windows: [], observedAt: nil, state: .live, plan: nil, creditBalance: nil)
        #expect(MenuUsageCard.freshness(of: missing, now: Self.now) == nil)
    }

    @Test("The panel, in Spanish, when asked for")
    func capture() throws {
        guard let directory = ProcessInfo.processInfo.environment["VIGIA_CAPTURE_DIR"] else { return }
        LocalizationSource.use(.spanish)
        defer { LocalizationSource.use(.system) }
        let now = Date()
        func at(_ hours: Double) -> Date { now.addingTimeInterval(hours * 3600) }
        func w(_ id: String, _ kind: UsageWindow.Kind, _ used: Double, _ seconds: Int, _ hours: Double,
               scope: String? = nil, exhausted: Bool = false) -> UsageWindow {
            UsageWindow(id: id, kind: kind, scope: scope, usedFraction: used, windowSeconds: seconds,
                        resetsAt: at(hours), isExhausted: exhausted,
                        label: scope.map { "\(kind == .fiveHour ? String.localized("5-hour limit") : String.localized("Weekly limit")) · \($0)" })
        }
        let cards: [(ProviderUsage, String)] = [
            (ProviderUsage(account: AccountKey(.claudeCode),
                           windows: [w("5h", .fiveHour, 0.81, 5 * 3600, 1.2), w("7d", .weekly, 0.14, 7 * 86_400, 106)],
                           observedAt: now.addingTimeInterval(-90), state: .live, plan: "Max", creditBalance: nil), "Claude Code"),
            (ProviderUsage(account: AccountKey(.grokBot), windows: [w("7d", .weekly, 0.17, 7 * 86_400, 140)],
                           observedAt: now.addingTimeInterval(-300), state: .live, plan: "SuperGrok", creditBalance: nil), "Grok Bot"),
            (ProviderUsage(account: AccountKey(.grok), windows: [w("7d", .weekly, 1, 7 * 86_400, 19.5, exhausted: true)],
                           observedAt: now.addingTimeInterval(-600), state: .live, plan: nil, creditBalance: nil), "Grok Build"),
            (ProviderUsage(account: AccountKey(.antigravity),
                           windows: [w("g5", .fiveHour, 0.024, 5 * 3600, 0.4, scope: "Gemini"),
                                     w("g7", .weekly, 0.013, 7 * 86_400, 160, scope: "Gemini"),
                                     w("c5", .fiveHour, 0, 5 * 3600, 1.3, scope: "Claude and GPT"),
                                     w("c7", .weekly, 0, 7 * 86_400, 161, scope: "Claude and GPT")],
                           observedAt: now.addingTimeInterval(-3 * 3600), state: .stale, plan: nil, creditBalance: nil), "Antigravity")
        ]
        let panel = VStack(spacing: 6) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                MenuUsageCard(usage: card.0, title: card.1, showsForecast: true, now: now)
            }
        }
        .padding(8)
        .background(Color(white: 0.2))
        .environment(\.colorScheme, .dark)
        .environment(\.usageWarningThreshold, 0.75)

        let renderer = ImageRenderer(content: panel)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let data = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appending(path: "panel-nuevo.png"))
    }
}
