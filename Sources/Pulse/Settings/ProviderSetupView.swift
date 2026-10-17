import SwiftUI

/// Why the chooser is open, which decides its wording and what comes ticked.
enum ProviderSetupMode: Equatable {
    /// Nothing is chosen yet, and the first launch found nothing ready to
    /// switch on by itself. At least one has to be ticked to finish.
    case initial
    /// An upgrade that supports services found on this Mac.
    case newlyDetected
    /// Opened from the welcome window, for anything it did not switch on.
    case addMore

    /// What arrives ticked. A first choice ticks everything found, signed in
    /// or not — the person is choosing anyway, and the likeliest choice is
    /// what they have. The other two tick only what works with no setup:
    /// they run alongside a choice already made, and a ticked row that then
    /// shows a sign-in error is a worse default than an unticked one.
    func preselected(
        from providers: Set<Provider>,
        detected: Set<Provider>,
        ready: Set<Provider>
    ) -> Set<Provider> {
        switch self {
        case .initial: providers.intersection(detected.union(ready))
        case .newlyDetected, .addMore: providers.intersection(ready)
        }
    }
}

struct ProviderSetupView: View {
    let settings: AppSettings
    let providers: [Provider]
    let mode: ProviderSetupMode
    let finish: (Set<Provider>) -> Void
    let dismiss: () -> Void
    @State private var selected: Set<Provider>

    init(
        settings: AppSettings,
        providers: [Provider],
        mode: ProviderSetupMode,
        finish: @escaping (Set<Provider>) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.settings = settings
        self.providers = providers
        self.mode = mode
        self.finish = finish
        self.dismiss = dismiss
        _selected = State(initialValue: mode.preselected(
            from: Set(providers), detected: settings.detectedProviders, ready: settings.readyProviders
        ))
    }

    private var isInitial: Bool { mode == .initial }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Grouped the way Settings lists them. Each group keeps the
                    // order it was handed: detected first, then by name.
                    ForEach(Provider.Billing.allCases, id: \.self) { billing in
                        let group = providers.filter { $0.billing == billing }
                        if !group.isEmpty {
                            Text(billing.sectionTitle)
                                .font(.headline)
                                .padding(.top, billing == Provider.Billing.allCases.first ? 4 : 20)
                                .padding(.bottom, 4)
                            ForEach(group) { provider in
                                ProviderSetupRow(
                                    provider: provider,
                                    detected: settings.detectedProviders.contains(provider),
                                    ready: settings.readyProviders.contains(provider),
                                    isSelected: Binding(
                                        get: { selected.contains(provider) },
                                        set: { enabled in
                                            if enabled { selected.insert(provider) }
                                            else { selected.remove(provider) }
                                        }
                                    )
                                )
                                Divider()
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            HStack {
                Button(String.localized("Select detected services")) {
                    selected.formUnion(Set(providers).intersection(settings.detectedProviders))
                }
                .disabled(Set(providers).isDisjoint(with: settings.detectedProviders))
                Spacer()
                Button(String.localized("Not now"), action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(String.localized("Done")) { finish(selected) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isInitial && selected.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 620, minHeight: 480)
        .id(settings.language)
    }

    private var title: String {
        switch mode {
        case .initial: .localized("Choose services to monitor")
        case .newlyDetected: .localized("New services detected")
        case .addMore: .localized("Add services")
        }
    }

    private var explanation: String {
        switch mode {
        case .initial:
            .localized("Choose at least one service. Pulse reads its login and checks usage only after you finish. You can change this later in Settings.")
        case .newlyDetected:
            .localized("This version supports more services found on your Mac. Choose any you want to add; your existing choices stay in place.")
        case .addMore:
            .localized("Choose any other services to monitor. The ones already on stay as they are.")
        }
    }
}

private struct ProviderSetupRow: View {
    let provider: Provider
    let detected: Bool
    /// Its own tool's login is saved, so it works as soon as it is ticked.
    let ready: Bool
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(alignment: .top, spacing: 12) {
                LobeIconView(provider: provider, size: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(provider.displayName).fontWeight(.medium)
                        if ready {
                            Text(localized: "Signed in on this Mac")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if detected {
                            Text(localized: "Detected on this Mac")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(provider.monitoringAccessDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 14)
    }
}

#Preview {
    ProviderSetupView(
        settings: AppSettings(enabledAccounts: []),
        providers: Provider.builtIn, mode: .initial,
        finish: { _ in }, dismiss: {}
    )
}
