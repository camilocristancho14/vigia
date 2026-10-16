import Foundation

/// Antigravity's limits, read from a language server running on this Mac.
///
/// The odd one out of the seventeen. There is no account endpoint to ask and no
/// stored login to borrow: Antigravity starts a `language_server` process of
/// its own and talks to it over HTTPS on the loopback interface, and that
/// process is the only thing that knows the quota. So this is the one provider
/// whose figures exist **only while something of Antigravity's is running** —
/// which is what `.antigravityNotRunning` says, rather than dressing it up as
/// a failure.
///
/// Three things have to be found, and not one of them can be assumed:
/// - **the process**, either inside an app bundle or the `agy` executable
///   on `PATH` (matched by that name alone, never as a substring of another
///   command);
/// - **the port**, because the server is started with a port of 0 — "take
///   any free one" — so it is a different port on every launch and anything
///   hardcoded is wrong by the next restart;
/// - **the CSRF token**, a per-launch UUID the desktop app passes as
///   `--csrf_token`. Without it that server answers `unauthenticated`. The
///   `agy` CLI does not put the flag on its argv; the header is omitted
///   rather than sent empty.
///
/// **More than one process can match, and most of them are the wrong one.**
/// Antigravity IDE runs two language servers and only one answers; the other
/// refuses this RPC outright. Taking the first match and giving up if it did
/// not work was a real fault — measured, the one that answers was second.
/// Every candidate is tried, and every port each of them listens on.
struct AntigravityUsageService: Sendable {
    /// The RPCs this uses. Antigravity is built on Codeium's language server,
    /// hence the `exa.` package and the `x-codeium-` header.
    ///
    /// Those two are all there is for a *quota*: of the methods the server
    /// exposes, not one has "usage" or "credit" in its name, and the summary
    /// is not written to disk. Per-conversation token rows, when `agy` has
    /// saved any, are read separately by `AntigravityCLIReader`. This call
    /// says how much of a quota is left and what the plan is called.
    private static let quotaMethod = "exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
    private static let statusMethod = "exa.language_server_pb.LanguageServerService/GetUserStatus"
    private static let csrfHeader = "x-codeium-csrf-token"

    /// Protobuf JSON name `forceRefresh`, verified in agy 1.2.9. The reply
    /// uses the same camel-case JSON (`remainingFraction`), and an unknown
    /// field is ignored, so an older server still answers the way `{}` did.
    /// An empty body is served from the in-memory quota cache.
    static let quotaRequestBody = Data(#"{"forceRefresh":true}"#.utf8)

    func fetch() async -> ProviderUsage {
        let servers = Self.locateServers()
        guard !servers.isEmpty else {
            return .unavailable(.antigravity, reason: .antigravityNotRunning)
        }

        // An answer with no limits in it is a real answer, but not a reason to
        // stop: with two servers up it is what the wrong one says. Held, and
        // reported only if nothing better turns up.
        var answeredEmpty = false
        // Whether anything answered at all. A server that refused this RPC is
        // still Antigravity running — reporting `.unreachable` for it would
        // say the app is not there while it is, and `.unreachable` is a
        // failure the notifications count while `.antigravityNotRunning` is
        // not. That regression arrived with the multi-origin search.
        var somethingAnswered = false

        for server in servers {
            // A server listens on more than one port and only one of them
            // speaks this. Which is which isn't advertised, so they are tried.
            for port in server.ports {
                switch await Self.ask(port: port, token: server.token) {
                case .success(let windows) where !windows.isEmpty:
                    return ProviderUsage(
                        account: AccountKey(.antigravity),
                        windows: windows,
                        observedAt: Date(),
                        state: .live,
                        // A second call, because the quota reply doesn't name
                        // the plan. Its absence is not worth failing over.
                        plan: await Self.plan(port: port, token: server.token),
                        // Antigravity reports a monthly credit *allowance*,
                        // never a balance. Putting an allowance here would read
                        // as "this is what you have left" — the one thing it
                        // isn't.
                        creditBalance: nil
                    )
                case .success:
                    answeredEmpty = true
                    somethingAnswered = true
                case .failure(.wrongPort):
                    continue
                case .failure(.refused):
                    // The other of Antigravity IDE's two servers answers 401 to
                    // this RPC. That is this process saying "not me", not the
                    // account being refused, so it is worth no more than a
                    // closed port — keep looking.
                    somethingAnswered = true
                    continue
                case .failure(.unreadable):
                    // A 200 whose body would not decode. Also not a reason to
                    // stop: "every candidate is tried" has to mean every
                    // candidate, or the first odd body ends the search and the
                    // server that would have answered is never asked.
                    somethingAnswered = true
                    continue
                }
            }
        }

        if answeredEmpty { return .unavailable(.antigravity, reason: .noLimitsReported) }
        // Something is running and would not answer, versus nothing answering
        // at all. Neither is a fault to be told about on a timer, and the
        // first attempt at this said `.unreadableReply` — which sits in
        // `AlertMemory.isFailure` right beside `.unreachable`, so the banner
        // the fix was written to stop went on firing about an app that was
        // open. The reason has to be one the classification actually spares.
        return .unavailable(
            .antigravity,
            reason: somethingAnswered ? .antigravityNotAnswering : .antigravityNotRunning
        )
    }

    // MARK: - Finding it

    /// Which Antigravity a language server belongs to, in the order they are
    /// asked.
    ///
    /// The app first. Both were measured to answer the same
    /// `RetrieveUserQuotaSummary` payload — the same two groups, the same
    /// weekly and five-hour buckets, the same reset times — so this ordering
    /// costs nothing when only one is running and settles it when both are.
    /// The app is the product these limits belong to; the IDE is an extension
    /// carrying a copy of the same server.
    private enum Origin: CaseIterable {
        case app
        case ide

        /// A fragment of the process's own path.
        ///
        /// The **bundle**, never the executable's name: `language_server` is
        /// Codeium's binary and its other editors ship the same one, which
        /// would otherwise be asked for Antigravity's quota and answer for
        /// something else. The IDE's copy is named `language_server_macos_arm`
        /// and still contains `/language_server`, so the name test below holds
        /// for both while these keep them apart.
        ///
        /// `/Antigravity.app/` does not match `/Antigravity IDE.app/` — the
        /// space is what separates them, and it is why these are written with
        /// their slashes.
        var pathFragment: String {
            switch self {
            case .app: "/Antigravity.app/"
            case .ide: "/Antigravity IDE.app/"
            }
        }
    }

    private struct Server {
        let ports: [Int]
        /// Nil for an `agy` process that was not started with `--csrf_token`.
        /// The header is then omitted.
        let token: String?
    }

    /// Every language server on this Mac that might be able to answer, best
    /// first: the app, the IDE, then a running `agy`.
    ///
    /// Plural, and that is the point: Antigravity IDE runs two of them and
    /// only one answers this RPC. One `ps` for all of them, then one `lsof`
    /// each — a process listening on nothing cannot be asked anything, so it
    /// is dropped here rather than being tried and timing out. If `agy` is
    /// up but `lsof` lists nothing, the ports from its newest live log are
    /// tried instead.
    private static func locateServers() -> [Server] {
        guard let listing = run("/bin/ps", ["-axww", "-o", "pid=,command="]) else { return [] }
        let lines = listing.split(separator: "\n").map(String.init)
        return appServers(in: lines) + cliServers(in: lines)
    }

    /// Desktop language servers, in `Origin` order. The bundle path is what
    /// keeps Codeium's other editors out, and `--csrf_token` is required:
    /// without it those servers answer `unauthenticated`.
    private static func appServers(in lines: [String]) -> [Server] {
        Origin.allCases.flatMap { origin in
            lines
                .filter { $0.contains("/language_server") && $0.contains(origin.pathFragment) }
                .compactMap { line -> Server? in
                    let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    guard
                        let pid = fields.first.flatMap(Int32.init),
                        let token = AntigravityCLISession.csrfToken(in: fields)
                    else { return nil }
                    let ports = listeningPorts(of: pid)
                    return ports.isEmpty ? nil : Server(ports: ports, token: token)
                }
        }
    }

    /// `agy` processes. The executable's last path component has to be `agy`;
    /// the rest of the command line is not consulted for the match.
    private static func cliServers(in lines: [String]) -> [Server] {
        var found: [Server] = []
        var liveWithoutPorts = false
        var fallbackToken: String?
        for line in lines {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard AntigravityCLISession.commandNamesAgy(fields), let pid = fields.first.flatMap(Int32.init) else {
                continue
            }
            let token = AntigravityCLISession.csrfToken(in: fields)
            let ports = listeningPorts(of: pid)
            if ports.isEmpty {
                liveWithoutPorts = true
                fallbackToken = fallbackToken ?? token
                continue
            }
            found.append(Server(ports: ports, token: token))
        }
        if found.isEmpty, liveWithoutPorts {
            let ports = AntigravityCLISession.liveLogPorts()
            if !ports.isEmpty {
                found.append(Server(ports: ports, token: fallbackToken))
            }
        }
        return found
    }

    /// Every loopback port the process is listening on.
    ///
    /// `-F n` asks `lsof` for just the names, one per line, which is far
    /// steadier to read than its columns.
    private static func listeningPorts(of pid: Int32) -> [Int] {
        guard let listing = run(
            "/usr/sbin/lsof",
            ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-F", "n"]
        ) else { return [] }

        return listing
            .split(separator: "\n")
            .compactMap { line in
                guard line.hasPrefix("n") else { return nil }
                return line.split(separator: ":").last.flatMap { Int($0) }
            }
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Asking it

    private enum Failure: Error {
        /// This port answered, but not with this service — try the next one.
        case wrongPort
        case refused
        case unreadable

        /// Kept for the shape of the enum; `fetch` decides the terminal
        /// reason itself now, because none of these means the same thing
        /// after every candidate has been tried as it does for one of them.
        var unavailability: ProviderUsage.Unavailability {
            switch self {
            case .wrongPort, .refused: .antigravityNotRunning
            case .unreadable: .unreadableReply
            }
        }
    }

    private static func ask(port: Int, token: String?) async -> Result<[UsageWindow], Failure> {
        switch await post(quotaMethod, port: port, token: token) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let data):
            guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
                return .failure(.unreadable)
            }
            return .success(windows(from: reply))
        }
    }

    /// The plan's name — "Pro", and whatever the other tiers are called.
    ///
    /// `GetUserStatus` answers with a good deal more than this, the account's
    /// name and email address among it. Only the plan's name is decoded: the
    /// rest is the user's, not ours, and nothing here has any use for it.
    private static func plan(port: Int, token: String?) async -> String? {
        guard
            case .success(let data) = await post(statusMethod, port: port, token: token),
            let reply = try? JSONDecoder().decode(StatusReply.self, from: data),
            let name = reply.userStatus?.planStatus?.planInfo?.planName,
            !name.isEmpty
        else { return nil }

        return name
    }

    private static func post(_ method: String, port: Int, token: String?) async -> Result<Data, Failure> {
        guard let url = URL(string: "https://127.0.0.1:\(port)/\(method)") else {
            return .failure(.wrongPort)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: csrfHeader)
        }
        request.httpBody = quotaRequestBody
        request.timeoutInterval = 6

        let session = URLSession(
            configuration: .ephemeral,
            delegate: LoopbackTrust(),
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        guard let (data, response) = try? await session.data(for: request) else {
            return .failure(.wrongPort)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .failure(.refused)
        default: return .failure(.wrongPort)
        }

        return .success(data)
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

        let response: Response?
    }

    /// Only the sliver of `GetUserStatus` that is any of Pulse's business.
    private struct StatusReply: Decodable {
        struct PlanInfo: Decodable { let planName: String? }
        struct PlanStatus: Decodable { let planInfo: PlanInfo? }
        struct UserStatus: Decodable { let planStatus: PlanStatus? }

        let userStatus: UserStatus?
    }

    static func windows(from reply: Reply) -> [UsageWindow] {
        (reply.response?.groups ?? []).flatMap { group -> [UsageWindow] in
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

/// Trusts the language server's certificate, and nothing else.
///
/// It signs its own, so the system has no way to vouch for it. The exception is
/// held to the loopback address: a certificate offered by anything other than
/// this Mac talking to itself is refused exactly as it would be anywhere else
/// in the app.
private final class LoopbackTrust: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            challenge.protectionSpace.host == "127.0.0.1",
            let trust = challenge.protectionSpace.serverTrust
        else {
            return completionHandler(.performDefaultHandling, nil)
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
