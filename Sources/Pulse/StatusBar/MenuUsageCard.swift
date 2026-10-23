// The status-item menu's card for one account: denser than the notch's
// bubble, because the menu stacks one per AI and the eye has to run down all
// of them. What is used and when it comes back sit in two fixed columns, so
// they line up from one limit to the next and from one card to the next; the
// colour is the risk; and the header says how fresh the figures are.
import SwiftUI

enum MenuCardLayout {
    static let width: CGFloat = 292
    static let padding: CGFloat = 10
    static let nameColumn: CGFloat = 88
    static let percentColumn: CGFloat = 34
    static let resetColumn: CGFloat = 76
    static let barHeight: CGFloat = 4
    static let cornerRadius: CGFloat = 12
    /// A reading older than this is no longer called fresh.
    static let freshFor: TimeInterval = 15 * 60
}

/// A translucent, softly bordered card background: Liquid Glass where the
/// system offers it, `.ultraThinMaterial` everywhere else. `#if
/// compiler(>=6.2)` keeps `glassEffect` (macOS 26+ SDK only) from breaking a
/// build on an older Xcode entirely — `if #available` alone only guards the
/// runtime check, not whether the symbol exists to compile against.
private extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            self.glassEffect(in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        #endif
    }
}

struct MenuUsageCard: View {
    let usage: ProviderUsage
    var title: String?
    var showsRemaining = false
    var showsForecast = false
    var resetCredits: CodexResetCredits?
    var now = Date()

    @Environment(\.usageWarningThreshold) private var warningThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            ForEach(usage.windows) { window in
                row(window)
            }

            if let resetCredits {
                fact(String.localized("Limit reset credits"), UsageDetailCard.resetCreditsText(resetCredits))
                if let expiry = UsageDetailCard.resetCreditExpiryText(resetCredits) {
                    fact(String.localized("Next expiry"), expiry)
                }
            }

            if usage.windows.isEmpty || usage.account.provider == .pulseExtension,
               let balance = usage.creditBalance {
                fact(String.localized("Credit balance"), balance)
            }

            if case .unavailable(let reason) = usage.state {
                note(reason.message)
            } else if usage.windows.isEmpty, usage.creditBalance == nil {
                note(ProviderUsage.Unavailability.noLimitsReported.message)
            }
        }
        .padding(MenuCardLayout.padding)
        .frame(width: MenuCardLayout.width, alignment: .leading)
        .glassCard(cornerRadius: MenuCardLayout.cornerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localized("\(title ?? usage.provider.displayName) usage details"))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            LobeIconView(provider: usage.provider, size: 16)
                .foregroundStyle(.primary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title ?? usage.provider.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                // Under the name, never beside it: a long name and "Updated
                // 3 min ago" do not share one line of a menu without one of
                // them being cut.
                HStack(spacing: 4) {
                    if let freshness = Self.freshness(of: usage, now: now) {
                        Circle().fill(freshness.colour).frame(width: 6, height: 6)
                        Text(verbatim: freshness.text)
                            .foregroundStyle(freshness.isFresh ? Color.secondary : freshness.colour)
                            .help(freshness.isFresh ? "" : String.localized("Reading may be out of date"))
                    }
                    if let plan = usage.plan, !plan.isEmpty {
                        Text(verbatim: "· \(plan)").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// How fresh the figures are, as the header says it: "Updated 3 min ago"
    /// with a green dot while fresh, the same words in amber once the reading
    /// is stale or old. Nil for a reading with no time on it.
    static func freshness(of usage: ProviderUsage, now: Date = Date())
        -> (text: String, colour: Color, isFresh: Bool)? {
        guard let observed = usage.observedAt else { return nil }
        if case .unavailable = usage.state { return nil }
        let stale: Bool = if case .stale = usage.state { true } else { false }
        let fresh = !stale && now.timeIntervalSince(observed) < MenuCardLayout.freshFor
        return (UsageDetailCard.updatedText(observed, now: now), fresh ? .pulseGood : .pulseCaution, fresh)
    }

    // MARK: Rows

    /// One thin line per limit: label, bar, percent, reset -- all the notch
    /// card's second screenful used to take two lines for.
    private func row(_ window: UsageWindow) -> some View {
        let spent = UsageTint.isSpent(window)
        let risk = Self.risk(of: window, warningAt: warningThreshold, forecast: showsForecast, now: now)
        let progress = showsRemaining ? window.remainingFraction : window.usedFraction
        let reset = Self.resetText(window, now: now)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 6) {
                Text(verbatim: window.name)
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: MenuCardLayout.nameColumn, alignment: .leading)
                bar(progress, colour: risk.colour)
                Text(verbatim: window.percentText(remaining: showsRemaining))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(spent ? Color.pulseExhausted : risk.colour == .pulseGood ? .primary : risk.colour)
                    .frame(width: MenuCardLayout.percentColumn, alignment: .trailing)
                HStack(spacing: 3) {
                    if !reset.isEmpty {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    Text(verbatim: reset)
                        .font(.system(size: 9.5, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.secondary)
                .frame(width: MenuCardLayout.resetColumn, alignment: .trailing)
            }

            if let warning = risk.warning {
                Text(verbatim: warning)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(risk.colour)
                    .lineLimit(1)
                    .padding(.leading, MenuCardLayout.nameColumn + 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.name)
        .accessibilityValue(
            showsRemaining
                ? String.localized("\(window.percentText(remaining: true)) left. \(UsageDetailCard.resetDescription(window))")
                : String.localized("\(window.percentText(remaining: false)) used. \(UsageDetailCard.resetDescription(window))")
        )
    }

    private func bar(_ fraction: Double, colour: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule().fill(colour)
                    // A sliver even at 0%, so an empty bar still says which
                    // colour it is in.
                    .frame(width: max(MenuCardLayout.barHeight, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: MenuCardLayout.barHeight)
    }

    /// The colour a limit is in and the one line of warning it earns: spent,
    /// on course to run out, or nothing. Colour follows the used share as the
    /// rings do, raised to the warning colour when the forecast says it will
    /// not last — a limit at 14% that will be gone in an hour is the risk.
    static func risk(of window: UsageWindow, warningAt: Double, forecast: Bool, now: Date = Date())
        -> (colour: Color, warning: String?) {
        if UsageTint.isSpent(window) {
            return (.pulseExhausted, .localized("Used up until it resets"))
        }
        let base = window.tint(warningAt: warningAt)
        guard forecast, let burn = BurnRate.reading(for: window, now: now), burn.exhaustsBeforeReset else {
            return (base, nil)
        }
        let warning: String = burn.timeToExhaustion.map { .localized("Runs out in \(BurnRate.approximate($0))") }
            ?? .localized("Won't last the window")
        return (.pulseWarning, warning)
    }

    /// When the limit comes back, short enough for its column: the time today,
    /// the date and time otherwise, the date alone past a week.
    static func resetText(_ window: UsageWindow, now: Date = Date()) -> String {
        guard let resets = window.resetsAt else { return window.reportsLength ? window.lengthText : "" }
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        let calendar = Calendar.current
        let template = calendar.isDate(resets, inSameDayAs: now) ? "jmm"
            : resets.timeIntervalSince(now) < 7 * 86_400 ? "EEEjmm" : "MMMd"
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: resets)
    }

    // MARK: Other lines

    private func fact(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(verbatim: value).monospacedDigit()
        }
        .font(.system(size: 11.5, design: .rounded))
        .lineLimit(1)
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11.5, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
