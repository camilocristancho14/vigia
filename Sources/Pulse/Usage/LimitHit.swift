import Foundation

/// A limit the agent itself reported hitting, read from its own transcript.
///
/// The usage endpoints are polled, and a limit is exactly the thing that moves
/// between two polls: a session can burn through its five hours in the gap
/// and the panel goes on saying there is room. The agent, though, is told the
/// moment it happens, and writes it down — Claude Code as an assistant record
/// carrying `error: "rate_limit"` and "You've hit your session limit · resets
/// 5pm (America/Bogota)", Codex as the `rate_limits` of its `token_count`
/// events. Those are local files, read every couple of seconds by the activity
/// monitor, so this is the one signal that is both exact and instant.
struct LimitHit: Equatable, Sendable {
    /// Which of a provider's limits it was.
    enum Window: Equatable, Sendable {
        /// The five-hour session window.
        case session
        /// The weekly window.
        case weekly
        /// A limit that is neither, or one that was not said: a per-model
        /// weekly limit, a message that names none.
        case other

        func matches(_ window: UsageWindow) -> Bool {
            switch (self, window.kind) {
            case (.session, .fiveHour), (.weekly, .weekly): true
            default: false
            }
        }
    }

    /// When the agent wrote it.
    let at: Date
    /// When the limit lifts, if the message said.
    let resetsAt: Date?
    let window: Window

    /// A hit that names no reset is believed for this long: long enough to
    /// cover a session window, short enough that a message nobody ever
    /// followed up does not hold a ring red for the rest of the week.
    static let unspecifiedTerm: TimeInterval = 5 * 3600

    /// Whether it still binds at `now`.
    func isActive(at now: Date) -> Bool {
        now < (resetsAt ?? at.addingTimeInterval(Self.unspecifiedTerm))
    }

    // MARK: - Reading the words

    /// Claude Code's message: "You've hit your session limit · resets 5pm
    /// (America/Bogota)", "…weekly limit · resets Oct 17, 3pm (…)", the older
    /// "Claude AI usage limit reached|1760000000".
    ///
    /// Nil for any other text. Matching on the words as well as on the
    /// record's `error` field is deliberate: the field has changed name before
    /// and the sentence is what the person reads.
    static func parseClaude(_ text: String, at stamp: Date, calendar: Calendar = .current) -> LimitHit? {
        if let range = text.range(of: #"usage limit reached\|(\d{10})"#, options: .regularExpression),
           let seconds = TimeInterval(text[range].dropFirst("usage limit reached|".count)) {
            return LimitHit(at: stamp, resetsAt: Date(timeIntervalSince1970: seconds), window: .session)
        }
        guard let hit = text.range(of: #"hit your ([A-Za-z0-9 .\-]+?) limit"#, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let which = text[hit].lowercased()
        let window: Window = which.contains("session") ? .session : which.contains("weekly") && !which.contains("opus")
            && !which.contains("sonnet") ? .weekly : .other
        return LimitHit(at: stamp, resetsAt: resetTime(in: text, after: stamp, calendar: calendar), window: window)
    }

    /// Claude Code's structured block: `{"status": "rejected", "resetsAt":
    /// 1791928800, "rateLimitType": "five_hour"}`. Only a rejection is a hit —
    /// the same block also rides on warnings that block nothing.
    static func parseClaudeInfo(_ info: [String: Any], at stamp: Date) -> LimitHit? {
        guard info["status"] as? String == "rejected" else { return nil }
        let window: Window = switch info["rateLimitType"] as? String {
        case "five_hour": .session
        case "seven_day": .weekly
        default: .other
        }
        let resets = (info["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return LimitHit(at: stamp, resetsAt: resets, window: window)
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// "resets 5pm (America/Bogota)", "resets 3:30pm", "resets Oct 17, 3pm".
    /// A bare time is the next time that clock reads it after `stamp`; a date
    /// is that date, rolling into next year only if it would otherwise be
    /// more than a day behind.
    static func resetTime(in text: String, after stamp: Date, calendar: Calendar = .current) -> Date? {
        let pattern = #"resets\s+(?:([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})(?:,|\s+at)?\s+)?(\d{1,2})(?::(\d{2}))?\s*([ap]m)(?:\s*\(([^)]+)\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }

        var calendar = calendar
        if let name = group(6), let zone = TimeZone(identifier: name) { calendar.timeZone = zone }
        guard var hour = group(3).flatMap(Int.init), let meridiem = group(5)?.lowercased(), (1...12).contains(hour)
        else { return nil }
        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }
        let minute = group(4).flatMap(Int.init) ?? 0

        var parts = calendar.dateComponents([.year, .month, .day], from: stamp)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        if let name = group(1)?.lowercased(), let month = months.firstIndex(of: name).map({ $0 + 1 }),
           let day = group(2).flatMap(Int.init) {
            parts.month = month
            parts.day = day
            guard var date = calendar.date(from: parts) else { return nil }
            if date < stamp.addingTimeInterval(-86_400), let next = calendar.date(byAdding: .year, value: 1, to: date) {
                date = next
            }
            return date
        }
        guard let today = calendar.date(from: parts) else { return nil }
        return today > stamp ? today : calendar.date(byAdding: .day, value: 1, to: today)
    }

    /// Codex's `rate_limits` block, as its `token_count` events carry it:
    /// `primary` and `secondary` each hold `used_percent`, `window_minutes`
    /// and `resets_at`. A hit when it says one was reached, or any window is
    /// at 100%.
    static func parseCodex(_ limits: [String: Any], at stamp: Date) -> LimitHit? {
        let reached = limits["rate_limit_reached_type"] as? String
        var spent: [(window: Window, resetsAt: Date?)] = []
        for key in ["primary", "secondary"] {
            guard let entry = limits[key] as? [String: Any],
                  let used = (entry["used_percent"] as? NSNumber)?.doubleValue, used >= 100 else { continue }
            let minutes = (entry["window_minutes"] as? NSNumber)?.intValue ?? 0
            let window: Window = minutes == 0 ? .other : minutes <= 360 ? .session : minutes >= 10_080 ? .weekly : .other
            let resets = (entry["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            spent.append((window, resets))
        }
        if let first = spent.first {
            return LimitHit(at: stamp, resetsAt: first.resetsAt, window: first.window)
        }
        if let reached, !reached.isEmpty {
            return LimitHit(at: stamp, resetsAt: nil, window: .other)
        }
        return nil
    }

    /// An agent that says only that it ran out, with no figures: Grok Build's
    /// failed turn. Whether the words mean a limit is judged by the caller.
    static func looksLikeLimit(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["usage limit", "rate limit", "limit reached", "limit exceeded", "out of credits", "quota"]
            .contains { lowered.contains($0) }
    }
}

extension UsageWindow {
    /// This window with a limit the agent hit laid over it, or unchanged when
    /// the hit does not apply: it is for another window, it has lifted, or the
    /// reading is newer than the hit and says something else.
    func applying(_ hit: LimitHit, readAt: Date?, now: Date = Date()) -> UsageWindow {
        guard hit.window.matches(self), hit.isActive(at: now) else { return self }
        // A reading taken after the hit is the provider's own word on it. Only
        // one older than the hit — or one that already agrees — is overridden.
        if let readAt, readAt > hit.at.addingTimeInterval(5), !isExhausted, usedFraction < 1 { return self }
        // A window the reading already says will have reset by then is a
        // different window from the one that was hit.
        if let resetsAt, resetsAt <= hit.at { return self }
        return UsageWindow(
            id: id, kind: kind, scope: scope, usedFraction: 1, windowSeconds: windowSeconds,
            resetsAt: hit.resetsAt ?? resetsAt, reportsLength: reportsLength, estimate: estimate,
            isExhausted: true, nextExpiry: nextExpiry, label: label
        )
    }
}
