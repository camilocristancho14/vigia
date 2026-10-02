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
/// `PreToolUse`, `PostToolUse`, `Stop`) POST a few bytes to this receiver.
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
    }

    private var entries: [String: Entry] = [:]
    private var owners: [String: Provider] = [:]
    private(set) var lastEvent: Date?

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
        let aliases: [String: Provider] = ["claude": .claudeCode]
        return aliases[wanted]
            ?? Provider.allCases.first { squash($0.rawValue) == wanted || squash($0.displayName) == wanted }
    }

    mutating func record(provider: Provider = .claudeCode, source: String, event: String, tool: String?, at now: Date) {
        let key = "\(provider.rawValue)/\(source.prefix(64))"
        owners[key] = provider
        switch event {
        case "UserPromptSubmit", "PostToolUse":
            entries[key] = Entry(working: true, wait: .model, label: "Thinking…", at: now)
        case "PreToolUse":
            let label = tool.map(AgentActivity.toolLabel) ?? "Using tool"
            entries[key] = Entry(working: true, wait: .tool, label: label, at: now)
        case "Stop", "SessionEnd":
            entries[key] = Entry(working: false, wait: .model, label: nil, at: now)
        default:
            return
        }
        lastEvent = now
        // A handful of sources is the realistic case; bound the table anyway.
        if entries.count > 32 {
            entries = entries.filter { now.timeIntervalSince($0.value.at) < AgentActivity.Wait.tool.grace }
            owners = owners.filter { entries[$0.key] != nil }
        }
    }

    func state(for provider: Provider = .claudeCode, now: Date) -> (isWorking: Bool, label: String?)? {
        let live = entries.filter { owners[$0.key] == provider }.map(\.value).filter {
            $0.working && now.timeIntervalSince($0.at) <= $0.wait.grace
        }
        guard let newest = live.max(by: { $0.at < $1.at }) else { return nil }
        return (true, newest.label)
    }
}

final class RemoteActivityReceiver: @unchecked Sendable {
    static let shared = RemoteActivityReceiver()
    static let port: UInt16 = 7717
    static let maximumBody = 4 * 1024

    private let queue = DispatchQueue(label: "com.pulse.remote-activity")
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
    func state(for provider: Provider = .claudeCode, now: Date = Date()) -> (isWorking: Bool, label: String?)? {
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
        lock.lock()
        ledger.record(provider: provider, source: source, event: event, tool: tool, at: Date())
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
    static let remoteActivityChanged = Notification.Name("com.pulse.remoteActivityChanged")
}
