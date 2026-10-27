import Foundation

/// One Grok card for what used to be three: Grok Build, Grok Bot and Cursor.
///
/// **Why they are one now.** With X's subscription the three are the same
/// purchase: the SuperGrok pool Grok Build reads, the Grok Bot allowance that
/// used to arrive through Cursor, and Cursor's own model pools are all spent
/// by one person on one plan. Three rings for one bill said three limits where
/// there is one, and two of them always read the same figure — the screenshot
/// that asked for this showed Grok Build and Grok Bot both at 100% with the
/// same reset.
///
/// The three readers stay as they are (each knows its own endpoint and its own
/// failure modes); this only decides what the single card shows:
/// - The weekly pool from Grok Build first. Grok Bot's weekly window only when
///   Grok Build reported none, because they are the same pool and showing both
///   is the duplicate this exists to remove.
/// - Cursor's pools after it, under the names Cursor gives them.
enum GrokUnifiedUsage {
    /// The providers folded into `.grok`. Left out of `Provider.builtIn`, so
    /// no list, chooser or rail offers them on their own.
    static let absorbed: Set<Provider> = [.grokBot, .cursor]

    static func merge(grok: ProviderUsage, grokBot: ProviderUsage, cursor: ProviderUsage) -> ProviderUsage {
        let account = grok.account
        let live = [grok, grokBot, cursor].filter { $0.state == .live && !$0.windows.isEmpty }

        // Nothing usable anywhere: report Grok Build's own reason, since its
        // login is the one this card is named for.
        guard !live.isEmpty else { return grok }

        var windows: [UsageWindow] = []
        if grok.state == .live { windows += grok.windows }
        if grokBot.state == .live, !windows.contains(where: { $0.kind == .weekly }) {
            windows += grokBot.windows
        }
        if cursor.state == .live {
            let taken = Set(windows.map(\.id))
            windows += cursor.windows.filter { !taken.contains($0.id) }
        }

        var merged = ProviderUsage(
            account: account,
            windows: windows,
            observedAt: live.compactMap(\.observedAt).max(),
            state: .live,
            plan: [grok, grokBot, cursor].lazy.filter { $0.state == .live }.compactMap(\.plan).first,
            creditBalance: nil
        )
        merged.origin = grok.state == .live ? grok.origin : live.first?.origin
        return merged
    }
}
