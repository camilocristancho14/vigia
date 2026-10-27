import CryptoKit
import Foundation
import Network

/// Claude Code, Grok Build or any other AI running somewhere else — a server, another computer, a bot
/// with a machine of its own — tells this Mac when it is working.
///
/// **Why it has to be told.** Everything else Vigía knows about activity is
/// read off this Mac's disk, and a remote session writes nothing here. The
/// account's usage figure already includes it, but says nothing about *now*.
/// So the remote side pushes: Claude Code's hooks (`UserPromptSubmit`,
/// `PreToolUse`, `PostToolUse`, `Stop`) POST a few bytes to this receiver —
/// `{provider, source, event, tool}` and, from newer hooks, a `kind` saying
/// whether a shell command is a test run or a build (see `CommandWait`).
///
/// **Off until switched on, and never open.** It listens on a network port,
/// so every request must carry the bearer token generated when it was first
/// enabled, bodies are capped at a few kilobytes, and nothing it receives is
/// ever executed or written to disk — it only moves a mascot. Reach it over a
/// private network (Tailscale, an SSH tunnel), not the public internet.

/// What the remote machines have said, folded into "is it working".
///
/// Pure and clock-injected so the rule can be tested without a socket. The
/// grace periods are the transcript reader's own (`AgentActivity.Wait`): a
/// turn waiting on a tool may be silent for minutes, one waiting on the model
/// should not be.
struct RemoteActivityLedger: Sendable {
    private struct Entry {
        var working: Bool
        var wait: AgentActivity.Wait
        var label: String?
        var at: Date
        /// The tool a `PreToolUse` named, and what its hook said the command
        /// was. The label is worked out when asked, because a shell command
        /// turns into a wait just by running long enough.
        var tool: String?
        var kind: CommandKind?

        /// Hard cap at 10 minutes regardless of tool or kind: a remote side
        /// that has gone silent (crashed, lost its network, box rebooted)
        /// must not be shown as working indefinitely just because it was
        /// last seen running a test or a build.
        var grace: TimeInterval { min(CommandWait.grace(ordinary: wait.grace, kind: kind), 10 * 60) }
    }

    private var entries: [String: Entry] = [:]
    private var owners: [String: Provider] = [:]
    private(set) var lastEvent: Date?

    /// Entries keyed by the `agent` name a hook names itself with (Dobby,
    /// Neo, ...), scoped by provider -- Grok Bot's box can run several of
    /// these at once, which the plain `entries`/`owners` tables above (keyed
    /// only by `source`) would otherwise collapse into one last-writer-wins
    /// line. A hook that never sends `agent` never populates this, so every
    /// other provider's behaviour is unchanged.
    private var agentEntries: [Provider: [String: Entry]] = [:]

    /// How long "Dobby finished" stays up after its last `Stop` before
    /// falling back to the ordinary idle text.
    private static let justFinishedGrace: TimeInterval = 5

    /// Which AI an event is about, from the name a remote machine gives it:
    /// a provider's identifier or its display name, in any case and with or
    /// without spaces and dashes ("claudeCode", "Grok Build", "grok-bot").
    /// Nothing at all means Claude Code, which is what the first version of
    /// this receiver spoke.
    static func provider(named name: String?) -> Provider? {
        guard let name, !name.isEmpty else { return .claudeCode }
        func squash(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let wanted = squash(name)
        // Grok Bot and Cursor are shown on the Grok card now
        // (`GrokUnifiedUsage`), so their hooks move that card's mark. The old
        // name of the card still reaches it too.
        let aliases: [String: Provider] = [
            "claude": .claudeCode,
            "grokbuild": .grok, "grokbot": .grok, "cursor": .grok,
        ]
        return aliases[wanted]
            ?? Provider.allCases.first { squash($0.rawValue) == wanted || squash($0.displayName) == wanted }
    }

    /// `kind` is the optional category a newer hook sends with a shell
    /// command (`"test"`, `"build"`); an older hook sends none, and a kind on
    /// any other tool is ignored.
    mutating func record(provider: Provider = .claudeCode, source: String, event: String, tool: String?,
                         kind: String? = nil, agent: String? = nil, at now: Date) {
        let key = "\(provider.rawValue)/\(source.prefix(64))"
        owners[key] = provider
        let entry: Entry
        switch event {
        case "UserPromptSubmit", "PostToolUse":
            entry = Entry(working: true, wait: .model, label: "Thinking…", at: now)
        case "PreToolUse":
            let label = tool.map(AgentActivity.toolLabel) ?? "Using tool"
            let kindValue = tool.map(CommandWait.isShell) == true ? CommandKind(named: kind) : nil
            entry = Entry(working: true, wait: .tool, label: label, at: now, tool: tool, kind: kindValue)
        case "Stop", "SessionEnd":
            entry = Entry(working: false, wait: .model, label: nil, at: now)
        default:
            return
        }
        entries[key] = entry
        // A Grok Bot hook that never names itself is still a Grok Bot: fold
        // it into the agent-keyed table under the generic name so it shows
        // as "Grok Bot working"/"Grok Bot finished" like a named one, rather
        // than silently falling back to the single-line behaviour meant for
        // providers that never send `agent` at all.
        let resolvedAgent: String?
        if let agent, !agent.isEmpty {
            resolvedAgent = agent
        } else if provider == .grokBot {
            resolvedAgent = "Grok Bot"
        } else {
            resolvedAgent = nil
        }
        if let resolvedAgent {
            agentEntries[provider, default: [:]][resolvedAgent] = entry
        }
        lastEvent = now
        // A handful of sources is the realistic case; bound the table anyway.
        if entries.count > 32 {
            entries = entries.filter { now.timeIntervalSince($0.value.at) < CommandWait.longGrace }
            owners = owners.filter { entries[$0.key] != nil }
        }
        if let perAgent = agentEntries[provider], perAgent.count > 32 {
            agentEntries[provider] = perAgent.filter { now.timeIntervalSince($0.value.at) < CommandWait.longGrace }
        }
    }

    /// Folds every named bot (Dobby, Neo, ...) that has posted its own
    /// `agent` field for this provider into one line: "Dobby working",
    /// "Dobby and Neo working", "3 bots working" -- or, for a few seconds
    /// after the last of them stops, "Dobby finished". `nil` when no agent
    /// has ever reported in for this provider, so `state(for:)` falls back
    /// to its ordinary single-entry behaviour untouched.
    func agentActivityText(for provider: Provider, now: Date) -> (text: String, since: Date?)? {
        guard let perAgent = agentEntries[provider], !perAgent.isEmpty else { return nil }

        var working: [(name: String, at: Date)] = []
        for (name, entry) in perAgent {
            let isLive: Bool = entry.working && now.timeIntervalSince(entry.at) <= entry.grace
            if isLive { working.append((name: name, at: entry.at)) }
        }
        working.sort { left, right in
            left.at == right.at ? left.name < right.name : left.at < right.at
        }

        if !working.isEmpty {
            var names: [String] = []
            for item in working { names.append(item.name) }
            let text: String
            switch names.count {
            case 1: text = String.localized("\(names[0]) working")
            case 2: text = String.localized("\(names[0]) and \(names[1]) working")
            default: text = String.localized("\(names.count) bots working")
            }
            return (text, working.first?.at)
        }

        var lastFinishedName: String?
        var lastFinishedAt: Date?
        for (name, entry) in perAgent {
            let justStopped: Bool = !entry.working && now.timeIntervalSince(entry.at) <= Self.justFinishedGrace
            guard justStopped else { continue }
            if lastFinishedAt == nil || entry.at > lastFinishedAt! {
                lastFinishedName = name
                lastFinishedAt = entry.at
            }
        }
        guard let finishedName = lastFinishedName, let finishedAt = lastFinishedAt else { return nil }
        return (String.localized("\(finishedName) finished"), finishedAt)
    }

    /// `since` is when the shell command it is waiting on started, while the
    /// label is one of `CommandWait`'s; nil otherwise.
    func state(for provider: Provider = .claudeCode, now: Date) -> (isWorking: Bool, label: String?, since: Date?)? {
        if let agentText = agentActivityText(for: provider, now: now) {
            return (true, agentText.text, agentText.since)
        }
        let live = entries.filter { owners[$0.key] == provider }.map(\.value).filter {
            $0.working && now.timeIntervalSince($0.at) <= $0.grace
        }
        guard let newest = live.max(by: { $0.at < $1.at }) else { return nil }
        guard newest.wait == .tool, let tool = newest.tool else { return (true, newest.label, nil) }
        let label = CommandWait.label(tool: tool, kind: newest.kind, running: now.timeIntervalSince(newest.at),
                                      toolLabel: AgentActivity.toolLabel)
        return (true, label, CommandWait.isWait(label) ? newest.at : nil)
    }
}

final class RemoteActivityReceiver: @unchecked Sendable {
    static let shared = RemoteActivityReceiver()
    static let port: UInt16 = 7717
    static let maximumBody = 4 * 1024

    private let queue = DispatchQueue(label: "com.vigia.remote-activity")
    private let lock = NSLock()
    private var listener: NWListener?
    private var ledger = RemoteActivityLedger()

    /// Whether the receiver is listening. Marks nobody can observe locally are
    /// only worth watching for activity while it is.
    var isEnabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return listener != nil
    }

    /// The remote side's current verdict, or nil when nothing is working.
    func state(for provider: Provider = .claudeCode, now: Date = Date()) -> (isWorking: Bool, label: String?, since: Date?)? {
        lock.lock(); defer { lock.unlock() }
        return ledger.state(for: provider, now: now)
    }

    func apply(enabled: Bool) {
        defer { NotificationCenter.default.post(name: .remoteActivityChanged, object: nil) }
        lock.lock(); defer { lock.unlock() }
        if enabled {
            guard listener == nil else { return }
            // Make sure a token exists before anything can connect.
            _ = Self.token()
            guard let port = NWEndpoint.Port(rawValue: Self.port),
                  let listener = try? NWListener(using: .tcp, on: port) else { return }
            listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
            listener.start(queue: queue)
            self.listener = listener
        } else {
            listener?.cancel()
            listener = nil
            ledger = RemoteActivityLedger()
        }
    }

    // MARK: - The token

    private static let tokenKey = "settings.remoteActivityToken"
    private static let tokenPurpose = "remote-activity-token"

    /// Created on first use and kept sealed to this Mac, like the other
    /// secrets Vigía holds.
    static func token() -> String {
        let defaults = UserDefaults.standard
        if let sealed = defaults.data(forKey: tokenKey),
           let plain = LocalSecrets.open(sealed, purpose: tokenPurpose),
           let text = String(data: plain, encoding: .utf8), text.count >= 32 {
            return text
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return "" }
        let fresh = bytes.map { String(format: "%02x", $0) }.joined()
        if let sealed = LocalSecrets.seal(Data(fresh.utf8), purpose: tokenPurpose) {
            defaults.set(sealed, forKey: tokenKey)
        }
        return fresh
    }

    // MARK: - One request

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        // A client that connects and says nothing must not hold the socket.
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) { [weak self] chunk, _, done, error in
            guard let self else { return }
            var buffer = accumulated
            if let chunk { buffer.append(chunk) }
            if buffer.count > 16 * 1024 || error != nil { return self.reply(connection, 413) }

            switch Self.parse(buffer) {
            case .incomplete:
                if done { connection.cancel() } else { self.receive(on: connection, accumulated: buffer) }
            case .rejected(let status):
                self.reply(connection, status)
            case .request(let authorization, let body):
                self.reply(connection, self.handle(authorization: authorization, body: body))
            }
        }
    }

    enum Parsed: Equatable {
        case incomplete
        case rejected(Int)
        case request(authorization: String?, body: Data)
    }

    /// `POST /activity`, a `Content-Length` within the cap, and the whole body.
    static func parse(_ data: Data) -> Parsed {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 8 * 1024 ? .rejected(431) : .incomplete
        }
        guard let head = String(data: data[..<split.lowerBound], encoding: .utf8) else { return .rejected(400) }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2, requestLine[0] == "POST", requestLine[1] == "/activity" else {
            return .rejected(404)
        }
        var authorization: String?
        var length = 0
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "authorization" { authorization = value }
            if name == "content-length" { length = Int(value) ?? -1 }
        }
        guard length >= 0, length <= maximumBody else { return .rejected(413) }
        let body = data[split.upperBound...]
        guard body.count >= length else { return .incomplete }
        return .request(authorization: authorization, body: Data(body.prefix(length)))
    }

    private func handle(authorization: String?, body: Data) -> Int {
        guard let authorization, authorization.hasPrefix("Bearer "),
              Self.constantTimeEqual(String(authorization.dropFirst(7)), Self.token())
        else { return 401 }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let event = json["event"] as? String
        else { return 400 }

        guard let provider = RemoteActivityLedger.provider(named: json["provider"] as? String) else { return 400 }
        let source = (json["source"] as? String) ?? "remote"
        let tool = json["tool"] as? String
        // Optional, and only ever a category: newer hooks classify the
        // command where it runs and never send the command itself.
        let kind = json["kind"] as? String
        // Optional: which named bot this is about (Dobby, Neo, ...), for
        // providers like Grok Bot that can run several at once under one
        // source. A hook that never sends it keeps the old single-line
        // behaviour.
        let agent = json["agent"] as? String
        lock.lock()
        ledger.record(provider: provider, source: source, event: event, tool: tool, kind: kind, agent: agent, at: Date())
        lock.unlock()
        return 204
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let left = Array(SHA256.hash(data: Data(a.utf8)))
        let right = Array(SHA256.hash(data: Data(b.utf8)))
        return zip(left, right).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0 && !b.isEmpty
    }

    private func reply(_ connection: NWConnection, _ status: Int) {
        let reason = [204: "No Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
                      413: "Payload Too Large", 431: "Request Header Fields Too Large"][status] ?? "Error"
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

extension Notification.Name {
    /// The receiver was switched on or off, so what is being watched changes.
    static let remoteActivityChanged = Notification.Name("com.vigia.remoteActivityChanged")
}
