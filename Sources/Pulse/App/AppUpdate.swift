// Modified for Vigía from Pulse (Apache-2.0).
// The Sparkle updater is not shipped. Updates come from GitHub Releases: the
// check reads the latest release, and the install is `AppUpdateInstaller`.
import AppKit
import Foundation
import Observation

/// What is known about a newer Vigía, and the one way to get it.
///
/// **The feed is GitHub's own "latest release" endpoint**, the same place the
/// README sends people to download from — so the version offered here and the
/// one on the releases page cannot disagree. No account, no token: the
/// endpoint is public and its rate limit (sixty an hour per address) is far
/// above one check a day.
///
/// Only a build running from a `.app` asks at all. `swift run` and the test
/// runner are a developer's tree, where "a newer version is out" is noise and
/// "replace this app" has nothing to replace.
///
/// Checked at launch and then at most once a day — the date of the last
/// answered check is kept in `UserDefaults`, so quitting and reopening ten
/// times on a morning is still one request. Settings → About has a button for
/// the person who does not want to wait for tomorrow.
@MainActor
@Observable
final class AppUpdate {
    struct Release: Equatable, Sendable {
        /// Without the tag's leading "v": what `CFBundleShortVersionString`
        /// says in the build that release shipped.
        let version: String
        /// The release's own page, which is where every failure ends up.
        let page: URL
        /// `Vigia.zip`, when the release has one. A release without it is
        /// still offered, and "Update now" opens the page instead.
        let archive: URL?
    }

    /// How far an install has got. Separate from `newer` because a failed
    /// install is still a newer version somebody can fetch by hand.
    enum InstallState: Equatable, Sendable {
        case idle
        case downloading
        /// Unpacked, checked and staged; the app is about to quit and reopen.
        case installing
        case failed(AppUpdateInstaller.Failure)
    }

    private(set) var newer: Release?
    private(set) var isChecking = false
    private(set) var didFail = false
    private(set) var install: InstallState = .idle

    /// Where every "it didn't work" sends people: the newest release, whatever
    /// its number.
    nonisolated static let releasesPage = URL(string: "https://github.com/camilocristancho14/vigia/releases/latest")!
    nonisolated static let feed = URL(string: "https://api.github.com/repos/camilocristancho14/vigia/releases/latest")!

    private static let lastCheckKey = "vigia.update.lastCheck"
    private static let automaticKey = "vigia.update.checksAutomatically"
    /// A day, less a little: a Mac opened at 9:00 one day and 8:55 the next
    /// should still check on the second morning.
    nonisolated static let checkInterval: TimeInterval = 23 * 60 * 60

    private let defaults: UserDefaults
    private var dailyTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// A `.app` with a version to compare. Anything else is a build from the
    /// source tree, and About says so rather than pretending to have checked.
    var canCheck: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && current != nil
    }

    /// On unless somebody turned it off: a person who installed from a DMG and
    /// never opens Settings is exactly who needs to be told.
    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return defaults.object(forKey: Self.automaticKey) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                defaults.set(newValue, forKey: Self.automaticKey)
            }
            if newValue { checkIfDue() }
        }
    }

    /// Asks now, whatever the date — the button in About.
    func check() {
        guard canCheck, !isChecking, let current else { return }
        isChecking = true
        didFail = false
        Task { [weak self] in
            let release = await Self.fetchLatest()
            guard let self else { return }
            self.isChecking = false
            guard let release else {
                self.didFail = true
                return
            }
            self.defaults.set(Date(), forKey: Self.lastCheckKey)
            self.newer = Self.isNewer(release.version, than: current) ? release : nil
            if self.newer == nil, case .failed = self.install { self.install = .idle }
        }
    }

    /// At launch, and from a timer for the Mac that is never quit: asks only
    /// when the last answer is a day old.
    func checkIfDue() {
        if dailyTimer == nil {
            // Every few hours is only how often the date is looked at; the
            // request itself still goes out once a day.
            let timer = Timer(timeInterval: 3 * 60 * 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkIfDue() }
            }
            RunLoop.main.add(timer, forMode: .common)
            dailyTimer = timer
        }
        guard checksAutomatically, canCheck,
              Self.isDue(lastCheck: defaults.object(forKey: Self.lastCheckKey) as? Date, now: Date())
        else { return }
        check()
    }

    /// "Update now". Downloads, checks and stages the new app, then hands the
    /// swap to a script that runs once this process has quit. Any failure
    /// leaves the installed app exactly as it was.
    func installNewer() {
        guard let newer else { return }
        switch install {
        case .downloading, .installing: return
        case .idle, .failed: break
        }
        guard let archive = newer.archive else {
            openReleasePage()
            return
        }
        install = .downloading
        Task { [weak self] in
            let result = await AppUpdateInstaller.prepare(
                archive: archive,
                expectedVersion: newer.version,
                installed: Bundle.main.bundleURL
            )
            guard let self else { return }
            switch result {
            case .failure(let failure):
                self.install = .failed(failure)
            case .success(let plan):
                self.install = .installing
                do {
                    try AppUpdateInstaller.launch(plan, waitingFor: ProcessInfo.processInfo.processIdentifier)
                } catch {
                    AppUpdateInstaller.discard(plan)
                    self.install = .failed(.couldNotLaunch)
                    return
                }
                // A beat for the menu or About to say "installing" before the
                // app goes; the script waits for this process whatever it takes.
                try? await Task.sleep(for: .milliseconds(400))
                NSApp.terminate(nil)
            }
        }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(Self.releasesPage)
    }

    // MARK: - Pure parts, tested

    /// Due when there is no record of a check, when the last one is a day old,
    /// or when the clock says it happened in the future (a date set back).
    nonisolated static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed < 0 || elapsed >= checkInterval
    }

    /// "v0.9.0" and "0.9.0" are the same version. Numbers only: anything that
    /// is not dot-separated digits after the "v" (a pre-release suffix, a
    /// branch name tagged by mistake) is not a version this compares, and a
    /// version it cannot read is never offered.
    nonisolated static func components(_ version: String) -> [Int]? {
        var text = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                  let number = Int(part) else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    /// Compared number by number, the shorter padded with zeros — so 0.10.0
    /// is past 0.9.0 (a string comparison says otherwise) and 1.0 is 1.0.0.
    nonisolated static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let a = components(candidate), let b = components(installed) else { return false }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The part of GitHub's release object this reads.
    private struct FeedRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?
    }

    /// The release a reply describes, or nil for anything that is not one: a
    /// draft or pre-release (the endpoint excludes them; a proxy's cached
    /// page might not), a tag that is not a version, an error body.
    nonisolated static func parseRelease(_ data: Data) -> Release? {
        guard let feed = try? JSONDecoder().decode(FeedRelease.self, from: data),
              feed.draft != true, feed.prerelease != true,
              let numbers = components(feed.tag_name)
        else { return nil }
        let version = numbers.map(String.init).joined(separator: ".")
        let assets = (feed.assets ?? []).map { (name: $0.name, url: $0.browser_download_url) }
        return Release(
            version: version,
            page: feed.html_url ?? releasesPage,
            archive: archive(among: assets)
        )
    }

    /// `Vigia.zip` by name; failing that, a zip whose name starts with the
    /// app's (a release renamed "Vigia-0.9.0.zip"). Never the DMG: mounting
    /// an image from a menu-bar app is a second thing that can go wrong, and
    /// the zip holds the same app.
    nonisolated static func archive(among assets: [(name: String, url: URL)]) -> URL? {
        if let exact = assets.first(where: { $0.name == "Vigia.zip" }) { return exact.url }
        return assets.first {
            let name = $0.name.lowercased()
            return name.hasSuffix(".zip") && (name.hasPrefix("vigia") || name.hasPrefix("vigía"))
        }?.url
    }

    nonisolated private static func fetchLatest() async -> Release? {
        var request = URLRequest(url: feed, timeoutInterval: 15)
        request.setValue("Vigia", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await NetworkSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return parseRelease(data)
    }
}
