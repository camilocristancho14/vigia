import Foundation
import Testing
@testable import Pulse

/// The renewal talks to an issuer nobody here can reach with a real login, so
/// every reply below is scripted through `GrokUsageService.send`.
@Suite("Grok login renewal")
struct GrokRenewalTests {
    private static func scratchFile(_ entry: [String: Any]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pulse-grok-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "auth.json")
        let data = try JSONSerialization.data(withJSONObject: ["https://auth.x.ai|client-1": entry])
        try data.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }

    // Computed rather than stored: `[String: Any]` is not Sendable, so a static `let` would not compile.
    private static var expiredEntry: [String: Any] {
        [
            "key": "old-token",
            "expires_at": "2020-01-01T00:00:00Z",
            "refresh_token": "refresh-1",
            "oidc_issuer": "https://auth.x.ai",
            "oidc_client_id": "client-1",
            "extra": "kept",
        ]
    }

    private static func reply(_ url: URL, _ status: Int, _ json: [String: Any]) -> (Data, URLResponse) {
        reply(url, status, body: (try? JSONSerialization.data(withJSONObject: json)) ?? Data())
    }

    private static func reply(_ url: URL, _ status: Int, body: Data) -> (Data, URLResponse) {
        (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private static func issuer(
        tokenStatus: Int = 200,
        tokenReply: [String: Any] = ["access_token": "new-token", "refresh_token": "refresh-2", "expires_in": 21_600],
        discovered: String? = nil
    ) -> @Sendable (URLRequest) async throws -> (Data, URLResponse) {
        // Serialised up front so the closure captures only Sendable `Data`.
        let tokenBody = (try? JSONSerialization.data(withJSONObject: tokenReply)) ?? Data()
        return { request in
            let url = request.url!
            if url.path.hasSuffix("openid-configuration") {
                guard let discovered else { return reply(url, 404, [:]) }
                return reply(url, 200, ["token_endpoint": discovered])
            }
            if url.host == "auth.x.ai", request.httpMethod == "POST" {
                return reply(url, tokenStatus, body: tokenBody)
            }
            // The billing proxy: only the renewed token is accepted.
            let accepted = request.value(forHTTPHeaderField: "Authorization") == "Bearer new-token"
            return reply(url, accepted ? 200 : 401, [:])
        }
    }

    @Test("An expired login is renewed and written back, keeping the rest of the file")
    func renewsAndWritesBack() async throws {
        let file = try Self.scratchFile(Self.expiredEntry)
        let outcome = await GrokLoginRenewal.shared.renew(authFile: file, rejecting: nil, send: Self.issuer())
        #expect(outcome == .renewed("new-token"))

        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let entry = try #require(root["https://auth.x.ai|client-1"] as? [String: Any])
        #expect(entry["key"] as? String == "new-token")
        #expect(entry["refresh_token"] as? String == "refresh-2")
        #expect(entry["extra"] as? String == "kept")
        #expect(entry["oidc_client_id"] as? String == "client-1")

        // And the service now sees a usable login without asking again.
        guard case .usable(let token) = GrokUsageService(authFile: file).storedLogin() else {
            Issue.record("expected the written-back login to be usable")
            return
        }
        #expect(token == "new-token")

        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test("A refresh the issuer rejects reads as an expired login")
    func rejectedRefreshIsExpired() async throws {
        let file = try Self.scratchFile(Self.expiredEntry)
        let service = GrokUsageService(authFile: file, send: Self.issuer(tokenStatus: 400, tokenReply: ["error": "invalid_grant"]))
        #expect(await service.fetch().state == .unavailable(.grokLoginExpired))
    }

    @Test("An unreachable issuer is not reported as an expired login")
    func unreachableIssuer() async throws {
        let file = try Self.scratchFile(Self.expiredEntry)
        let service = GrokUsageService(authFile: file, send: { _ in throw URLError(.notConnectedToInternet) })
        #expect(await service.fetch().state == .unavailable(.unreachable))
    }

    @Test("An entry with no refresh token cannot be renewed")
    func noRefreshToken() async throws {
        var entry = Self.expiredEntry
        entry["refresh_token"] = nil
        let file = try Self.scratchFile(entry)
        let outcome = await GrokLoginRenewal.shared.renew(authFile: file, rejecting: nil, send: Self.issuer())
        #expect(outcome == .rejected)
    }

    @Test("A discovered token endpoint on another host is never used")
    func foreignTokenEndpointIgnored() async throws {
        let file = try Self.scratchFile(Self.expiredEntry)
        let seen = Seen()
        let send: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            if request.httpMethod == "POST" { await seen.add(request.url!.host ?? "") }
            return try await Self.issuer(discovered: "https://evil.example/token")(request)
        }
        _ = await GrokLoginRenewal.shared.renew(authFile: file, rejecting: nil, send: send)
        #expect(await seen.hosts == ["auth.x.ai"])
    }

    @Test("A token another process already renewed is used without asking the issuer")
    func alreadyRenewedElsewhere() async throws {
        var entry = Self.expiredEntry
        entry["key"] = "cli-token"
        entry["expires_at"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3_600))
        let file = try Self.scratchFile(entry)
        let outcome = await GrokLoginRenewal.shared.renew(
            authFile: file, rejecting: "stale-token", send: { _ in throw URLError(.cannotConnectToHost) }
        )
        #expect(outcome == .renewed("cli-token"))
    }

    private actor Seen {
        var hosts: [String] = []
        func add(_ host: String) { hosts.append(host) }
    }
}
