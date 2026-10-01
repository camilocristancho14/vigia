// Modified for Vigía from Pulse (Apache-2.0).
// The Sparkle updater is not shipped. Installs come from GitHub Releases.
import Foundation
import Observation

/// Update checks are intentionally absent.
///
/// Vigía is installed from GitHub Releases. This type keeps the surface the
/// menu and the settings window already call, and always reports that a
/// check cannot be made.
@MainActor
@Observable
final class AppUpdate {
    struct Release: Equatable, Sendable {
        let version: String
    }

    private(set) var newer: Release?
    private(set) var isChecking = false
    private(set) var didFail = false

    var current: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var canCheck: Bool { false }

    var checksAutomatically: Bool {
        get { false }
        set { }
    }

    func check() {}

    func checkIfDue() {}
}
