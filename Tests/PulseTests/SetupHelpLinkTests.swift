import Foundation
import Testing
@testable import Pulse

/// "Setup help" and "Installation guide" open pages in this repository, so
/// every page they can name has to exist in it.
@Suite("Setup help links")
struct SetupHelpLinkTests {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The file inside the checkout a GitHub link points at, or nil when the
    /// link leaves Vigía's repository.
    private static func checkoutFile(for url: URL) -> URL? {
        let prefix = "https://github.com/camilocristancho14/vigia/blob/main/"
        guard url.absoluteString.hasPrefix(prefix) else { return nil }
        return repository.appending(path: String(url.absoluteString.dropFirst(prefix.count)))
    }

    @Test("Every provider's help page is Vigía's own and is in the repository", arguments: Provider.allCases)
    func providerPage(_ provider: Provider) throws {
        let url = ConnectionRemedy.helpURL(for: provider)
        let file = try #require(Self.checkoutFile(for: url), "\(url) is not in Vigía's repository")
        #expect(FileManager.default.fileExists(atPath: file.path), "missing \(file.path)")
    }

    @Test("The extension and integration guides are in the repository")
    func guides() throws {
        for url in [ExtensionsSettingsView.guideURL, DeveloperIntegrationsView.guideURL] {
            let file = try #require(Self.checkoutFile(for: url))
            #expect(FileManager.default.fileExists(atPath: file.path), "missing \(file.path)")
        }
    }

    @Test("The exported developer kit holds what Settings copies")
    func integrationKit() {
        let kit = Self.repository.appending(path: "Integrations")
        for file in DeveloperIntegrationsView.kitFiles {
            #expect(FileManager.default.fileExists(atPath: kit.appending(path: file).path), "missing \(file)")
        }
    }
}
