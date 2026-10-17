import Foundation

/// The Google login `agy` saved, and its renewal.
///
/// Read only: `agy`'s file is never written. See `AntigravityUsageService`.
enum AgyLogin {
    struct Saved: Equatable, Sendable {
        let accessToken: String?
        let refreshToken: String?
        let expiry: Date?
    }

    /// `{"token":{"access_token","refresh_token","expiry"}, ...}`, the Go
    /// `oauth2.Token` shape. Nil when there is no login to read at all.
    static func read(_ file: URL) -> Saved? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> Saved? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let token = root["token"] as? [String: Any] ?? root
        func text(_ key: String) -> String? {
            (token[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        let access = text("access_token")
        let refresh = text("refresh_token")
        guard access != nil || refresh != nil else { return nil }
        return Saved(accessToken: access, refreshToken: refresh, expiry: text("expiry").flatMap(date(from:)))
    }

    /// Go writes RFC 3339 with nanoseconds and a numeric offset.
    static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        // Nanoseconds are more digits than the formatter accepts; trim to millis.
        let trimmed = text.replacingOccurrences(
            of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression
        )
        if let date = fractional.date(from: trimmed) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    /// Google's installed-app client for `agy`. The ID is public; the secret,
    /// though Google does not treat it as one for installed apps, is read
    /// from the binary instead of being kept in this repository.
    static let clientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// Where `agy` is installed. Symlinks are followed.
    static func binaryCandidates(home: URL) -> [URL] {
        let paths = [
            home.appending(path: ".local/bin/agy").path,
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
        ]
        return paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
    }

    /// The first `GOCSPX-` secret in the binary, found by a byte scan of the
    /// memory-mapped file. Go's strings are not NUL-terminated, so the secret
    /// is cut at its fixed length — the marker and 28 characters — rather
    /// than wherever the next non-alphanumeric byte happens to be.
    static func clientSecret(home: URL) -> String? {
        let marker = Data("GOCSPX-".utf8)
        let length = marker.count + 28
        for url in binaryCandidates(home: home) {
            guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { continue }
            var searchFrom = data.startIndex
            while let range = data.range(of: marker, in: searchFrom..<data.endIndex) {
                let end = range.lowerBound + length
                if end <= data.endIndex, data[range.upperBound..<end].allSatisfy(isSecretByte),
                   let secret = String(data: data[range.lowerBound..<end], encoding: .ascii) {
                    return secret
                }
                searchFrom = range.upperBound
            }
        }
        return nil
    }

    private static func isSecretByte(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
            || byte == 0x2D || byte == 0x5F
    }

    enum Outcome: Equatable, Sendable {
        case usable(String)
        /// No refresh token, or Google refused it: `agy` has to sign in again.
        case rejected
        /// Google could not be asked. Worth retrying, not worth alarming.
        case unreachable
    }

    /// Holds a renewed access token until it lapses, and serialises renewals.
    actor Renewal {
        static let shared = Renewal()

        private var cached: (token: String, expiry: Date)?
        private var secret: String?

        /// A token that should work now. `rejecting` is one Google just
        /// refused, which is then never handed out again.
        func accessToken(
            for saved: Saved,
            home: URL,
            rejecting rejected: String? = nil,
            now: Date = Date()
        ) async -> Outcome {
            let margin: TimeInterval = 60
            if let cached, cached.token != rejected, cached.expiry > now.addingTimeInterval(margin) {
                return .usable(cached.token)
            }
            if let access = saved.accessToken, access != rejected,
               let expiry = saved.expiry, expiry > now.addingTimeInterval(margin) {
                return .usable(access)
            }
            guard let refresh = saved.refreshToken else { return .rejected }
            if secret == nil { secret = AgyLogin.clientSecret(home: home) }
            guard let secret else { return .rejected }

            var request = URLRequest(url: AgyLogin.tokenEndpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = AgyLogin.form([
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": AgyLogin.clientID,
                "client_secret": secret,
            ])

            guard let (body, response) = try? await URLSession.shared.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode
            else { return .unreachable }

            switch status {
            case 200: break
            case 400, 401, 403: return .rejected
            default: return .unreachable
            }

            guard let reply = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let token = reply["access_token"] as? String, !token.isEmpty
            else { return .unreachable }

            let seconds = (reply["expires_in"] as? Double) ?? 3_600
            cached = (token, now.addingTimeInterval(seconds))
            return .usable(token)
        }
    }

    static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let text = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
        return Data(text.utf8)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
