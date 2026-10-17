import Foundation

/// Antigravity's limits, read with the login the `agy` CLI saved on this Mac.
///
/// The way Claude Code, Codex and Grok Build are read: from the credentials
/// the CLI already keeps, straight from the service. Nothing of Antigravity's
/// has to be running — no app, no `agy` session, no language server — and
/// nothing asks the user to open one.
///
/// - **The login** is `~/.gemini/jetski-standalone-oauth-token`, a Google
///   OAuth token (`access_token`, `refresh_token`, `expiry`) written by `agy`.
/// - **The quota** is `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary`,
///   the call `agy`'s embedded language server makes itself. It answers the
///   same groups and buckets the local RPC did, without its `response` wrapper.
/// - **The plan** comes from `loadCodeAssist`, read the way Gemini CLI's is.
///
/// **Renewal stays in memory.** The access token lasts an hour. When it has
/// lapsed it is renewed from the refresh token as Google's installed-app
/// client `agy` itself is, and the result is kept here until it lapses too.
/// Google does not rotate that refresh token, so `agy`'s file is never
/// written. The client's secret is read out of the installed `agy` binary
/// rather than copied into this repository.
struct AntigravityUsageService: Sendable {
    static let quotaEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    static let loadCodeAssistEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!

    /// Empty. The language server took `forceRefresh`, but Google's endpoint
    /// refuses it as an unknown field (400), and always answers fresh anyway.
    static let quotaRequestBody = Data("{}".utf8)

    /// Google gates this API on the client: without a user agent naming
    /// Antigravity it answers 403 "no valid license", whatever the login.
    static let userAgent = "antigravity"

    var home = URL(fileURLWithPath: NSHomeDirectory())

    func fetch() async -> ProviderUsage {
        let tokenFile = home.appending(path: ".gemini/jetski-standalone-oauth-token")
        guard let saved = AgyLogin.read(tokenFile) else {
            return .unavailable(.antigravity, reason: .localLoginMissing)
        }

        let token: String
        switch await AgyLogin.Renewal.shared.accessToken(for: saved, home: home) {
        case .usable(let value): token = value
        case .rejected: return .unavailable(.antigravity, reason: .localLoginExpired)
        case .unreachable: return .unavailable(.antigravity, reason: .unreachable)
        }

        var quota = await Self.post(Self.quotaEndpoint, token: token, body: Self.quotaRequestBody)
        if case .failure(.refused) = quota {
            // Revoked or lapsed early: one renewal, then the answer stands.
            guard case .usable(let renewed) = await AgyLogin.Renewal.shared.accessToken(
                for: saved, home: home, rejecting: token
            ) else { return .unavailable(.antigravity, reason: .localLoginExpired) }
            quota = await Self.post(Self.quotaEndpoint, token: renewed, body: Self.quotaRequestBody)
        }

        switch quota {
        case .failure(.refused):
            return .unavailable(.antigravity, reason: .localLoginExpired)
        case .failure(.unreachable):
            return .unavailable(.antigravity, reason: .unreachable)
        case .success(let data):
            guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
                return .unavailable(.antigravity, reason: .unreadableReply)
            }
            let windows = Self.windows(from: reply)
            guard !windows.isEmpty else { return .unavailable(.antigravity, reason: .noLimitsReported) }
            return ProviderUsage(
                account: AccountKey(.antigravity),
                windows: windows,
                observedAt: Date(),
                state: .live,
                plan: await Self.plan(token: token),
                // Antigravity reports a monthly credit *allowance*, never a
                // balance; putting it here would read as what is left.
                creditBalance: nil
            )
        }
    }

    // MARK: - Asking Google

    enum Failure: Error, Equatable {
        case refused
        case unreachable
    }

    /// The plan's name, from the same lookup Gemini CLI's provider makes.
    /// Best-effort: its absence is not worth failing over.
    private static func plan(token: String) async -> String? {
        let body = Data(#"{"metadata":{"ideType":"ANTIGRAVITY","pluginType":"GEMINI"}}"#.utf8)
        guard case .success(let data) = await post(loadCodeAssistEndpoint, token: token, body: body) else { return nil }
        return GeminiUsageService.codeAssist(from: data).plan
    }

    private static func post(_ url: URL, token: String, body: Data) async -> Result<Data, Failure> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return .failure(.unreachable) }

        switch status {
        case 200..<300: return .success(data)
        case 401, 403: return .failure(.refused)
        default: return .failure(.unreachable)
        }
    }

    // MARK: - Reading the reply

    /// Internal rather than private, and deliberately: this and `windows(from:)`
    /// below are the halves a test can hold a real captured payload against,
    /// and the parsing is the part of this file most likely to be broken by a
    /// change at the other end. Nothing outside the module can see them. Do
    /// not tidy them back to `private` — that takes the fixture test with it.
    struct Reply: Decodable {
        struct Bucket: Decodable {
            let bucketId: String?
            let window: String?
            let remainingFraction: Double?
            let resetTime: String?
        }

        struct Group: Decodable {
            let displayName: String?
            let buckets: [Bucket]?
        }

        struct Response: Decodable {
            let groups: [Group]?
        }

        /// Google's endpoint answers with the groups at the top level; the
        /// language server's copy of the same message wrapped them in
        /// `response`. Both are read so the captured fixture keeps working.
        let response: Response?
        let groups: [Group]?

        var allGroups: [Group] { response?.groups ?? groups ?? [] }
    }

    static func windows(from reply: Reply) -> [UsageWindow] {
        reply.allGroups.flatMap { group -> [UsageWindow] in
            let scope = modelGroup(group.displayName)

            return (group.buckets ?? [])
                .compactMap { window(from: $0, scope: scope) }
                // Shortest window first within a group, which is the order the
                // other two providers' limits arrive in and the order they are
                // useful in: the one about to bite comes first.
                .sorted { $0.windowSeconds < $1.windowSeconds }
        }
    }

    private static func window(from bucket: Reply.Bucket, scope: String?) -> UsageWindow? {
        guard
            let id = bucket.bucketId,
            let remaining = bucket.remainingFraction,
            let (kind, seconds) = length(of: bucket.window)
        else { return nil }

        // The only provider that reports what is *left* rather than what is
        // gone. Everything downstream is in terms of what is gone.
        let used = min(max(1 - remaining, 0), 1)

        return UsageWindow(
            id: id,
            kind: kind,
            scope: scope,
            usedFraction: used,
            windowSeconds: seconds,
            resetsAt: bucket.resetTime.flatMap(Self.date(from:)),
            isExhausted: remaining <= 0
        )
    }

    /// A bucket whose window can't be read is left out rather than guessed at.
    ///
    /// `5h` and `weekly` are what the server sends today; the numbered forms
    /// are there so a new window length is understood rather than dropped. A
    /// window with no length can't be named or sorted, and inventing one would
    /// put a figure under a heading that isn't true.
    private static func length(of window: String?) -> (UsageWindow.Kind, Int)? {
        guard let window = window?.lowercased() else { return nil }

        switch window {
        case "5h": return (.fiveHour, 5 * 3_600)
        case "weekly": return (.weekly, 7 * 86_400)
        case "daily": return (.other(seconds: 86_400), 86_400)
        case "monthly": return (.other(seconds: 30 * 86_400), 30 * 86_400)
        default: break
        }

        guard let unit = window.last, let count = Int(window.dropLast()), count > 0 else { return nil }

        switch unit {
        case "h": return count == 5 ? (.fiveHour, 5 * 3_600) : (.other(seconds: count * 3_600), count * 3_600)
        case "d":
            let seconds = count * 86_400
            return count == 7 ? (.weekly, seconds) : (.other(seconds: seconds), seconds)
        default: return nil
        }
    }

    /// "Gemini Models" → "Gemini". The group's name is what the limit is
    /// scoped to, and it is shown after the window's own name — "5-hour limit ·
    /// Gemini" — where the trailing "models" is a word the row can't spare.
    private static func modelGroup(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }

        let words = name.split(separator: " ")
        guard words.count > 1, words.last?.lowercased() == "models" else { return name }
        return words.dropLast().joined(separator: " ")
    }

    /// Built per call rather than kept as a shared instance: `ISO8601DateFormatter`
    /// is not `Sendable`, and this parses at most a handful of stamps a refresh.
    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
