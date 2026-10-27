import Foundation

/// Restoring a choice is separate from discovering installed tools. Discovery
/// can suggest rows, but can never authorize a credential read.
struct ProviderSelection: Equatable {
    let enabledAccounts: Set<String>
    let suggestedProviders: Set<Provider>
    /// Nothing of any release has run with these defaults before: no choice,
    /// no offered list, no launch. The one case in which a first launch may
    /// switch ready providers on by itself (`AppDelegate.beginFirstRun`) —
    /// anyone who has seen Vigía before, including someone who closed the
    /// chooser empty, is asked instead.
    var isFreshInstall = false

    var needsSelection: Bool { enabledAccounts.isEmpty }

    // The existing keys also describe older releases. In 1.0.0 the enabled
    // list was absent until edited; its offered list was the implicit default.
    static let enabledKey = "settings.enabledProviders"
    static let offeredKey = "settings.offeredProviders"
    static let hasRunKey = "settings.hasRun"

    static func restore(
        in defaults: UserDefaults,
        knownAccounts: Set<String>,
        detected: Set<Provider>
    ) -> Self {
        let offered = defaults.stringArray(forKey: offeredKey)
        let isFresh = defaults.object(forKey: hasRunKey) == nil
            && defaults.object(forKey: enabledKey) == nil
            && defaults.object(forKey: offeredKey) == nil
        let stored: [String]?
        if defaults.object(forKey: enabledKey) != nil {
            // An empty or malformed stored choice is not 1.0.0's absent key.
            stored = defaults.stringArray(forKey: enabledKey) ?? []
        } else {
            stored = nil
        }
        var chosen = Set(stored ?? offered ?? [])
        // Grok Bot and Cursor are part of the Grok card now: whoever had
        // either switched on keeps seeing those figures, on that card.
        if !chosen.isDisjoint(with: GrokUnifiedUsage.absorbed.map(\.rawValue)) {
            chosen.insert(Provider.grok.rawValue)
        }
        let enabled = chosen.intersection(knownAccounts)
        let knownProviders = Set(offered ?? Provider.builtIn.map(\.rawValue))
        let suggestions = Set(Provider.builtIn.filter {
            !enabled.isEmpty && !knownProviders.contains($0.rawValue)
                && !enabled.contains($0.rawValue) && detected.contains($0)
        })

        // First-run dismissal keeps an explicit empty choice, so it asks again
        // next launch. Upgrade suggestions are offered once, even if dismissed.
        defaults.set(Array(enabled).sorted(), forKey: enabledKey)
        defaults.set(Provider.builtIn.map(\.rawValue), forKey: offeredKey)
        defaults.set(true, forKey: hasRunKey)
        return Self(enabledAccounts: enabled, suggestedProviders: suggestions, isFreshInstall: isFresh)
    }
}
