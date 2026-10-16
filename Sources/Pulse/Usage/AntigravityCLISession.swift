import Foundation

/// Whether the `agy` terminal CLI is open, working, or waiting, read from
/// the files it already writes. Quota stays with `AntigravityUsageService`:
/// this type never dials the language server and never starts `agy`.
///
/// What was checked on a real `agy` 1.2.9 install, and what was not:
///
/// - The CLI embeds its language server. It logs
///   `Language server listening on random port at N for HTTPS` and the same
///   sentence `for HTTP`, then a bare line `CLI ready for user input` (no
///   glog prefix — the time is the previous prefixed line), and
///   `Terminal gone, shutting down` when the terminal closes.
/// - `Print mode: starting` is a real line from a `--print` launch.
/// - `conversation_summaries.not_fully_idle` and `killed` are real columns.
///   No row on the machine that was inspected had a `status` value, so
///   status strings are not interpreted.
/// - `Surfacing tool confirmation:` and `cleared pending tool confirmation`
///   are printf formats recovered from the `agy` binary. No captured log
///   line contained them. They are recognised, and nothing else is invented
///   from that binary.
/// - There is no on-disk quota document and no `brain/transcript.jsonl` for
///   this build. Token rows, when a conversation database exists, stay with
///   `AntigravityCLIReader` under `antigravity-cli/conversations` only.
enum AntigravityCLISession {
    struct Summary: Equatable, Sendable {
        var notFullyIdle: Bool
        var killed: Bool
        var lastModified: Date?
    }

    struct Reading: Equatable, Sendable {
        var isWorking = false
        var isWaiting = false
        var label: String?
        var lastWrite: Date?
        /// The newest log ends in `Terminal gone`. Ports from that log
        /// belong to a server that has shut down.
        var sessionEnded = false
        var httpsPort: Int?
        var httpPort: Int?

        var ports: [Int] {
            var found: [Int] = []
            if let httpsPort { found.append(httpsPort) }
            if let httpPort, httpPort != httpsPort { found.append(httpPort) }
            return found
        }
    }

    /// The pure read. `year` comes from the log's own name
    /// (`cli-YYYYMMDD_HHMMSS.log`); glog stamps carry month and day only.
    static func reading(
        log text: String,
        year: Int,
        summaries: [Summary] = [],
        processRunning: Bool,
        now: Date,
        timeZone: TimeZone = .current
    ) -> Reading {
        var https: Int?
        var http: Int?
        var events: [Event] = []
        var lastStamp: Date?

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if let stamp = glogDate(line, year: year, timeZone: timeZone) {
                lastStamp = stamp
            }
            if let port = listenPort(in: line, https: true) {
                https = port
            } else if let port = listenPort(in: line, https: false) {
                http = port
            }
            if let signal = signal(in: line) {
                events.append(Event(signal: signal, at: lastStamp))
            }
        }

        let logEnded = events.last?.signal == .terminalGone
        if let busy = newestBusy(summaries) {
            let at = busy.lastModified
            if let at {
                let latest = events.last?.at
                let shutdown = events.last?.signal == .terminalGone
                let newer = latest.map { shutdown ? at > $0 : at >= $0 } ?? true
                if newer { events.append(Event(signal: .summaryBusy, at: at)) }
            } else if events.isEmpty {
                events.append(Event(signal: .summaryBusy, at: nil))
            }
        }

        var reading = Reading()
        reading.httpsPort = https
        reading.httpPort = http
        reading.sessionEnded = logEnded
        guard let event = events.last else {
            if processRunning { reading.lastWrite = now }
            return reading
        }

        switch event.signal {
        case .terminalGone:
            reading.lastWrite = event.at
        case .toolConfirmation:
            let fresh = event.at.map { now.timeIntervalSince($0) <= AgentActivity.waitingWindow } ?? false
            if processRunning || fresh {
                reading.isWaiting = true
                reading.lastWrite = processRunning ? now : event.at
            } else {
                reading.lastWrite = event.at
            }
        case .printMode, .toolCleared:
            if processRunning {
                reading.isWorking = true
                reading.label = "Thinking…"
                reading.lastWrite = now
            } else {
                reading.lastWrite = event.at
            }
        case .summaryBusy:
            let fresh = event.at.map { now.timeIntervalSince($0) <= AgentActivity.Wait.tool.grace } ?? false
            if processRunning || fresh {
                reading.isWorking = true
                reading.label = "Thinking…"
                reading.lastWrite = processRunning ? now : event.at
            } else {
                reading.lastWrite = event.at
            }
        case .ready:
            reading.lastWrite = processRunning ? now : event.at
        }
        return reading
    }

    /// `~/.gemini/antigravity-cli` under `home`, plus whether an `agy`
    /// process is up. The process check is the caller's, so a test with a
    /// fixture home does not depend on whoever is logged in on the machine.
    static func state(
        home: URL,
        processRunning: Bool,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> AgentActivity.State {
        let text: String
        let year: Int
        if let file = newestLogFile(home: home), let body = contents(of: file.url) {
            text = body
            year = file.year
        } else {
            text = ""
            year = Calendar.current.component(.year, from: now)
        }
        let found = reading(
            log: text,
            year: year,
            summaries: summaries(home: home, timeZone: timeZone),
            processRunning: processRunning,
            now: now,
            timeZone: timeZone
        )
        var state = AgentActivity.State(lastWrite: found.lastWrite, isWorking: found.isWorking, label: found.label)
        state.isWaiting = found.isWaiting
        return state
    }

    /// Ports from the newest CLI log, when that log does not end in
    /// `Terminal gone`. Empty when the only ports on disk belong to a
    /// session that already shut down. `lsof` is preferred; this is the
    /// fallback for a live `agy` whose listen sockets could not be listed.
    static func liveLogPorts(home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> [Int] {
        guard let file = newestLogFile(home: home), let body = contents(of: file.url) else { return [] }
        let found = reading(log: body, year: file.year, processRunning: false, now: Date())
        guard !found.sessionEnded else { return [] }
        return found.ports
    }

    /// The executable, never an argument. A Grok Build command line that is
    /// *about* `agy` contains the letters and must not count as the CLI.
    static func commandNamesAgy(_ fields: [String]) -> Bool {
        guard fields.count >= 2 else { return false }
        return URL(fileURLWithPath: fields[1]).lastPathComponent == "agy"
    }

    /// `--csrf_token` when the process was started with one. `agy` itself
    /// does not put that flag on its argv; the desktop app does. Nil means
    /// the header is omitted, not sent empty.
    static func csrfToken(in fields: [String]) -> String? {
        guard let index = fields.firstIndex(of: "--csrf_token"), fields.index(after: index) < fields.endIndex else {
            return nil
        }
        let token = fields[fields.index(after: index)]
        guard !token.isEmpty, !token.hasPrefix("-") else { return nil }
        return token
    }

    /// Whether some process's executable is named `agy`.
    static func processIsRunning() -> Bool {
        guard let listing = run("/bin/ps", ["-axww", "-o", "pid=,command="]) else { return false }
        for line in listing.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if commandNamesAgy(fields) { return true }
        }
        return false
    }

    // MARK: - Log lines

    private enum Signal {
        case ready
        case printMode
        case toolCleared
        case toolConfirmation
        case terminalGone
        case summaryBusy
    }

    private struct Event {
        var signal: Signal
        var at: Date?
    }

    private struct LogFile {
        var url: URL
        var year: Int
    }

    /// Phrases taken from captured logs, except the two confirmation
    /// sentences, which are the binary's format strings.
    private static func signal(in line: String) -> Signal? {
        if line.contains("Terminal gone, shutting down") { return .terminalGone }
        if line.contains("Surfacing tool confirmation:") { return .toolConfirmation }
        if line.contains("cleared pending tool confirmation") { return .toolCleared }
        if line.contains("Print mode: starting") { return .printMode }
        if line.contains("CLI ready for user input") { return .ready }
        return nil
    }

    /// `for HTTPS` contains the letters of `for HTTP`, so the secure line
    /// is matched first and never also counted as the plain one.
    private static func listenPort(in line: String, https: Bool) -> Int? {
        guard line.contains("Language server listening on random port at ") else { return nil }
        if https {
            guard line.contains("for HTTPS") else { return nil }
        } else {
            guard line.contains("for HTTP"), !line.contains("for HTTPS") else { return nil }
        }
        guard let range = line.range(of: "random port at ") else { return nil }
        let digits = line[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    /// `I0923 11:58:16.325607`. The level letter is I, W, E or F.
    static func glogDate(_ line: String, year: Int, timeZone: TimeZone) -> Date? {
        guard let first = line.first, "IWEF".contains(first) else { return nil }
        let rest = line.dropFirst()
        guard rest.count >= 14, rest.dropFirst(4).first == " " else { return nil }
        guard
            let month = Int(rest.prefix(2)),
            let day = Int(rest.dropFirst(2).prefix(2))
        else { return nil }
        let clock = rest.dropFirst(5)
        guard clock.count >= 8 else { return nil }
        let hourIndex = clock.startIndex
        let minuteIndex = clock.index(hourIndex, offsetBy: 3)
        let secondIndex = clock.index(hourIndex, offsetBy: 6)
        guard clock[clock.index(hourIndex, offsetBy: 2)] == ":", clock[clock.index(hourIndex, offsetBy: 5)] == ":" else {
            return nil
        }
        guard
            let hour = Int(clock[hourIndex..<clock.index(hourIndex, offsetBy: 2)]),
            let minute = Int(clock[minuteIndex..<clock.index(minuteIndex, offsetBy: 2)]),
            let second = Int(clock[secondIndex..<clock.index(secondIndex, offsetBy: 2)])
        else { return nil }

        var nanosecond = 0
        if clock.dropFirst(8).first == "." {
            let digits = clock.dropFirst(9).prefix { $0.isNumber }.prefix(9)
            if let raw = Int(digits) {
                nanosecond = raw
                var width = digits.count
                while width < 9 {
                    nanosecond *= 10
                    width += 1
                }
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second, nanosecond: nanosecond
        ))
    }

    static func year(in filename: String) -> Int? {
        guard filename.hasPrefix("cli-") else { return nil }
        let digits = filename.dropFirst(4).prefix(4)
        guard digits.count == 4, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    private static func newestBusy(_ summaries: [Summary]) -> Summary? {
        summaries
            .filter { $0.notFullyIdle && !$0.killed }
            .max { ($0.lastModified ?? .distantPast) < ($1.lastModified ?? .distantPast) }
    }

    private static func newestLogFile(home: URL) -> LogFile? {
        let directory = home.appending(path: ".gemini/antigravity-cli/log")
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let logs = urls.filter { $0.lastPathComponent.hasPrefix("cli-") && $0.pathExtension == "log" }
        guard let url = logs.max(by: { $0.lastPathComponent < $1.lastPathComponent }) else { return nil }
        let year = year(in: url.lastPathComponent) ?? Calendar.current.component(.year, from: Date())
        return LogFile(url: url, year: year)
    }

    /// Whole file up to 8MB. Past that, the head (listen ports) and the tail
    /// (the latest decisive line) are kept and the middle is not.
    private static func contents(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        let cap = 8 * 1024 * 1024
        guard data.count > cap else { return String(decoding: data, as: UTF8.self) }
        let head = String(decoding: data.prefix(256 * 1024), as: UTF8.self)
        let tail = String(decoding: data.suffix(2 * 1024 * 1024), as: UTF8.self)
        return head + "\n" + tail
    }

    private static func summaries(home: URL, timeZone: TimeZone) -> [Summary] {
        let url = home.appending(path: ".gemini/antigravity-cli/conversation_summaries.db")
        let rows = AgentSQLite.read(at: url) { database -> [Summary] in
            var found: [Summary] = []
            AgentSQLite.each(
                database,
                sql: """
                SELECT not_fully_idle, killed, last_modified_time
                FROM conversation_summaries
                """
            ) { statement in
                found.append(Summary(
                    notFullyIdle: isSet(AgentSQLite.text(statement, 0)),
                    killed: isSet(AgentSQLite.text(statement, 1)),
                    lastModified: AgentSQLite.text(statement, 2).flatMap { timestamp($0, timeZone: timeZone) }
                ))
            }
            return found
        }
        return rows ?? []
    }

    private static func isSet(_ text: String?) -> Bool {
        switch text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true": true
        default: false
        }
    }

    /// ISO-8601, SQLite's `YYYY-MM-DD HH:MM:SS`, or a unix number. Anything
    /// else is nil: an unreadable stamp does not count as "just now".
    private static func timestamp(_ text: String, timeZone: TimeZone) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSS"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        guard let seconds = Double(trimmed), seconds > 1_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
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
}
