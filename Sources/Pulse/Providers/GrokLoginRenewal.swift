import Foundation

/// Renews the CLI's login from the `refresh_token` it stored beside the access
/// token, so Pulse keeps reading without `grok` being started.
///
/// A plain OIDC refresh against the entry's own `oidc_issuer`, as a public
/// client (`oidc_client_id`, no secret). Three things are deliberate:
/// - **The result is written back to `~/.grok/auth.json`.** Issuers may rotate
///   the refresh token; renewing without saving would burn the one the CLI
///   still holds and sign the user out of it. The rest of the file is carried
///   over untouched and its permissions kept.
/// - **Renewals are serialised**, and the file is read again before asking. A
///   pass already in flight, or the CLI itself, may have renewed it a moment ago.
/// - **The token endpoint must be on the issuer's own host.** It is found
///   through discovery, and a refresh token is never sent anywhere else.
actor GrokLoginRenewal {
    static let shared = GrokLoginRenewal()

    enum Outcome: Equatable, Sendable {
        case renewed(String)
        /// No refresh token, or the issuer refused it: the user has to sign in.
        case rejected
        /// The issuer could not be asked. Worth retrying, not worth alarming.
        case unreachable
    }

    func renew(
        authFile: URL,
        rejecting rejected: String?,
        send: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async -> Outcome {
        // Someone else may have got there first.
        if case .usable(let token) = GrokUsageService(authFile: authFile).storedLogin(), token != rejected {
            return .renewed(token)
        }

        guard
            let data = try? Data(contentsOf: authFile),
            var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let (name, entry) = Self.renewableEntry(in: root),
            let refreshToken = entry["refresh_token"] as? String,
            let issuer = (entry["oidc_issuer"] as? String).flatMap(URL.init(string:)),
            let clientID = entry["oidc_client_id"] as? String,
            issuer.scheme == "https", let host = issuer.host
        else { return .rejected }

        let endpoint = await tokenEndpoint(issuer: issuer, host: host, send: send)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.form([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])

        guard let (body, response) = try? await send(request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return .unreachable }

        switch status {
        case 200: break
        // `invalid_grant` is a 400 and some issuers say 401: either way the
        // refresh token is no good. Anything else is the issuer's trouble.
        case 400, 401, 403: return .rejected
        default: return .unreachable
        }

        guard
            let reply = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let accessToken = reply["access_token"] as? String, !accessToken.isEmpty
        else { return .unreachable }

        var renewed = entry
        renewed["key"] = accessToken
        if let rotated = reply["refresh_token"] as? String, !rotated.isEmpty {
            renewed["refresh_token"] = rotated
        }
        if let seconds = (reply["expires_in"] as? Double) ?? (reply["expires_in"] as? String).flatMap(Double.init) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            renewed["expires_at"] = formatter.string(from: Date().addingTimeInterval(seconds))
        }
        root[name] = renewed
        Self.write(root, to: authFile)

        return .renewed(accessToken)
    }

    /// The entry most worth renewing: one that can be, preferring the one that
    /// lasts longest. Internal for the tests.
    static func renewableEntry(in root: [String: Any]) -> (String, [String: Any])? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        func expiry(_ entry: [String: Any]) -> Date {
            guard let text = entry["expires_at"] as? String else { return .distantPast }
            return fractional.date(from: text) ?? plain.date(from: text) ?? .distantPast
        }

        return root
            .compactMap { name, value -> (String, [String: Any])? in
                guard let entry = value as? [String: Any],
                      let token = entry["refresh_token"] as? String, !token.isEmpty,
                      entry["oidc_issuer"] is String, entry["oidc_client_id"] is String
                else { return nil }
                return (name, entry)
            }
            .max { expiry($0.1) < expiry($1.1) }
    }

    /// From the issuer's discovery document, falling back to the conventional
    /// path. A discovered endpoint on any other host is ignored.
    private func tokenEndpoint(
        issuer: URL,
        host: String,
        send: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async -> URL {
        let fallback = issuer.appending(path: "oauth2/token")

        var request = URLRequest(url: issuer.appending(path: ".well-known/openid-configuration"))
        request.timeoutInterval = 8

        guard
            let (data, response) = try? await send(request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = document["token_endpoint"] as? String,
            let url = URL(string: text),
            url.scheme == "https", url.host == host
        else { return fallback }

        return url
    }

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let text = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
        return Data(text.utf8)
    }

    /// Atomic, and the CLI's own permissions kept — the file holds a login.
    private static func write(_ root: [String: Any], to file: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return }
        let permissions = (try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]) ?? 0o600
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
    }
}
