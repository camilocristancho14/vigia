import Foundation
import Security

/// How far along a provider is on this Mac, from nothing to working.
///
/// **Why there are three answers and not two.** Discovery used to say one
/// thing — "something of this tool is here" — and that was only ever good for
/// a label in the chooser, because a folder from a tool nobody signed in to
/// is not a ring that will show anything. What makes a first launch quick is
/// the stronger fact: the tool's own login is saved, so the provider works the
/// moment it is switched on, with nothing pasted and nothing to configure.
/// That is `ready`, and it is the only answer that may switch anything on, and
/// only on a first launch (see `AppDelegate.beginFirstRun`). `installed` is the
/// old hint, kept for the chooser's label and for the welcome window's "sign
/// in first" list.
///
/// **Existence only, still.** The rule `installedOnThisMac` set — a hint is
/// never permission to read — holds here too. Every answer comes from whether
/// a file, a command or a keychain item *is there*: nothing is opened, parsed
/// or decrypted, so a check can never raise a Keychain prompt. The price is
/// that a login file that has expired still reads as ready; the ring then says
/// so with its own remedy, which is where an expired login was always shown.
enum ProviderReadiness: Int, Comparable, Sendable {
    /// Nothing of it on this Mac.
    case notFound
    /// Its app, its command-line tool or its folder is here, but not a login
    /// Vigía could use without being told something first.
    case installed
    /// Its own tool's login is saved: switched on, it reads with no setup.
    case ready

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Everything readiness looks at, handed in so a test can describe a Mac
/// without one: a home folder, which paths exist, what a folder lists, which
/// keychain items exist, and the folders a command may be found in.
struct DiscoveryProbe {
    var home: URL
    var exists: (String) -> Bool
    /// Names in a folder — for the Node managers' version folders and the
    /// JetBrains settings folders. Empty when there is no such folder.
    var list: (String) -> [String]
    /// Whether a generic-password item with this service name exists. Never
    /// its secret: see `DiscoveryProbe.keychainItemExists(service:)`.
    var hasKeychainItem: (String) -> Bool
    /// The `PATH` to search before the usual folders, as folders.
    var searchPath: [String]
    /// Whether a path is a program that can be run. `exists` for a test.
    var isExecutable: (String) -> Bool

    /// This Mac. `searchPath` defaults to Vigía's own `PATH`, which for an app
    /// opened from Finder is `/usr/bin:/bin:/usr/sbin:/sbin`; pass the login
    /// shell's (`LoginShellPath.resolve()`) for a better answer.
    static func live(searchPath: [String]? = nil) -> Self {
        let files = FileManager.default
        return Self(
            home: URL(fileURLWithPath: NSHomeDirectory()),
            exists: { files.fileExists(atPath: $0) },
            list: { (try? files.contentsOfDirectory(atPath: $0))?.sorted() ?? [] },
            hasKeychainItem: keychainItemExists(service:),
            searchPath: searchPath ?? LoginShellPath.folders(in: ProcessInfo.processInfo.environment["PATH"]),
            isExecutable: { files.isExecutableFile(atPath: $0) }
        )
    }

    /// Folders some tools install themselves into that `CommandLocator`'s
    /// shared list does not name, because nothing reads those tools through
    /// it: Claude Code's old local install, Grok's and OpenCode's own
    /// installers, cargo and deno.
    func toolDirectories() -> [String] {
        let home = home.path
        return [
            "\(home)/.claude/local",
            "\(home)/.grok/bin",
            "\(home)/.opencode/bin",
            "\(home)/.amp/bin",
            "\(home)/.cargo/bin",
            "\(home)/.deno/bin",
        ]
    }

    /// Whether the command can be found the way `CommandLocator` finds one:
    /// `PATH`, then the usual folders, then the Node managers' versions.
    func hasCommand(_ name: String) -> Bool {
        CommandLocator.candidates(
            name,
            home: home.path,
            path: searchPath.joined(separator: ":"),
            extra: toolDirectories().map { "\($0)/\(name)" },
            versions: list
        )
        .contains(where: isExecutable)
    }

    /// Asks only whether the item is there. With no `kSecReturn…` key the
    /// query returns nothing at all, so there is no secret to hand over and
    /// nothing for the system to ask permission for — reading the attributes
    /// or the data is what can prompt, and this does neither.
    static func keychainItemExists(service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // Present but locked away behind a prompt still means present.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}

extension Provider {
    /// Every built-in provider that is more than `notFound`.
    static func readiness(on probe: DiscoveryProbe) -> [Provider: ProviderReadiness] {
        var found: [Provider: ProviderReadiness] = [:]
        for provider in builtIn {
            let readiness = provider.readiness(on: probe)
            if readiness != .notFound { found[provider] = readiness }
        }
        // Cursor and Grok Bot are read on Grok's card, so finding either is
        // finding something for that card to show.
        if found[.grok] == nil,
           GrokUnifiedUsage.absorbed.contains(where: { $0.readiness(on: probe) != .notFound }) {
            found[.grok] = .ready
        }
        return found
    }

    func readiness(on probe: DiscoveryProbe) -> ProviderReadiness {
        let installed = discoveryPaths(home: probe.home).contains(where: probe.exists)
            || discoveryCommands.contains(where: probe.hasCommand)
        guard isSignedIn(on: probe) else { return installed ? .installed : .notFound }
        // A login it cannot be read without: the tool reads it for Vigía.
        if let tool = commandNeededToRead, !probe.hasCommand(tool) { return .installed }
        return .ready
    }

    /// Whether this provider can ever be `ready` — that is, whether it can work
    /// from a login its own tool saves rather than from something pasted.
    /// These are the ones the welcome window offers a way to sign in to.
    var canBeReadyWithoutSetup: Bool {
        if self == .jetBrainsAI { return true }
        return !loginPaths(home: URL(fileURLWithPath: "/")).isEmpty || !loginKeychainServices.isEmpty
    }

    private func isSignedIn(on probe: DiscoveryProbe) -> Bool {
        if self == .jetBrainsAI {
            return !JetBrainsAIUsageService.quotaFiles(home: probe.home, list: probe.list, exists: probe.exists).isEmpty
        }
        // Grok Bot is read with Cursor's login, but that login says nothing
        // about whether this account uses Grok Bot. Its own app does.
        if self == .grokBot, !discoveryPaths(home: probe.home).contains(where: probe.exists) {
            return false
        }
        return loginPaths(home: probe.home).contains(where: probe.exists)
            || loginKeychainServices.contains(where: probe.hasKeychainItem)
    }

    /// What `ProviderProfile.loginPaths` says, for the providers written by
    /// hand. Only what each service actually reads its login from — see the
    /// service named beside each.
    func loginPaths(home: URL) -> [String] {
        func local(_ path: String) -> String { home.appending(path: path).path }
        guard let written = handWritten else {
            return (profile?.loginPaths ?? []).map { $0.hasPrefix("/") ? $0 : local($0) }
        }
        switch written {
        // `ClaudeCodeUsageService.credentialsFile`, when the CLI is not using
        // the keychain — see `loginKeychainServices` for when it is.
        case .claudeCode: return [local(".claude/.credentials.json")]
        case .codex: return [local(".codex/auth.json")]
        // Kiro CLI keeps its sign-in in its own database; Vigía asks the CLI,
        // and never opens it.
        case .kiro: return [local("Library/Application Support/kiro-cli/data.sqlite3")]
        case .grok: return [local(".grok/auth.json")]
        case .antigravity: return [local(".gemini/jetski-standalone-oauth-token")]
        // `CursorAppLogin`'s database, for both rings it reads.
        case .cursor, .grokBot:
            return [local("Library/Application Support/Cursor/User/globalStorage/state.vscdb")]
        case .glmCoding:
            return [".coding-relay/glm-api-key", ".config/bigmodel/api_key", ".config/zhipu/api_key"].map(local)
        case .commandCode: return [local(".commandcode/auth.json")]
        // OpenCode's `auth.json` holds every provider it was signed in to, so
        // it being there does not say there is an OpenCode Go key in it — and
        // finding out would mean reading it. A hint, not readiness.
        case .openCodeGo: return []
        // A key, a browser session or a sign-in Vigía runs itself.
        case .devin, .qoder, .stepFun, .kimiCode, .ollamaCloud, .zai, .minimax, .minimaxCN,
             .copilot, .volcengine, .deepSeek, .xiaomiMiMo, .sub2api, .newAPI, .v2ex, .pulseExtension:
            return []
        }
    }

    /// Keychain items whose presence means the provider's tool is signed in.
    var loginKeychainServices: [String] {
        self == .claudeCode ? [ClaudeCodeUsageService().keychainService] : []
    }

    /// Command-line tools whose presence says the provider is installed.
    var discoveryCommands: [String] {
        guard let written = handWritten else { return profile?.discoveryCommands ?? [] }
        switch written {
        case .claudeCode: return ["claude"]
        case .codex: return ["codex"]
        case .kiro: return ["kiro-cli"]
        case .grok: return ["grok"]
        case .antigravity: return ["agy"]
        case .cursor: return ["cursor", "cursor-agent"]
        case .openCodeGo: return ["opencode"]
        case .kimiCode: return ["kimi"]
        case .volcengine: return ["arkcli"]
        case .qoder: return ["qodercli"]
        case .copilot: return ["copilot"]
        case .grokBot, .glmCoding, .commandCode, .devin, .stepFun, .ollamaCloud, .zai, .minimax,
             .minimaxCN, .deepSeek, .xiaomiMiMo, .sub2api, .newAPI, .v2ex, .pulseExtension:
            return []
        }
    }

    /// A saved login that only the provider's own program can read for Vigía:
    /// Kiro is asked through `kiro-cli`, and agy's login is renewed with the
    /// client secret inside the `agy` binary (`AgyLogin`). Without the program
    /// the login is there and still unusable, so it is not `ready`.
    private var commandNeededToRead: String? {
        switch self {
        case .kiro: "kiro-cli"
        case .antigravity: "agy"
        default: nil
        }
    }
}

/// The `PATH` a terminal would have.
///
/// An app opened from Finder inherits launchd's `PATH` — four system folders —
/// so a CLI the person runs every day is invisible to it by name. The login
/// shell knows where they put things: nvm, bun, pnpm, an installer's own
/// folder, all added in `.zshrc` or `.zprofile`. So the shell is asked, once,
/// on the first launch, and never waited on for long: it runs interactive to
/// read `.zshrc`, and somebody's `.zshrc` can do anything, so a slow or stuck
/// one costs at most `deadline` and then is not heard from again. Nothing
/// depends on the answer but which tools are labelled installed.
enum LoginShellPath {
    static let marker = "__VIGIA_PATH__"

    /// The shell's `PATH` as folders, or `fallback`'s when the shell is slow,
    /// fails or cannot be started.
    static func resolve(
        deadline: TimeInterval = 2.5,
        shell shellPath: String? = ProcessInfo.processInfo.environment["SHELL"],
        fallback: String? = ProcessInfo.processInfo.environment["PATH"]
    ) async -> [String] {
        let inherited = folders(in: fallback)
        let environment = ProcessInfo.processInfo.environment
        guard let shell = shell(from: shellPath) else { return inherited }
        // Not a task group: a group waits for every child before it returns,
        // and `BoundedProcess` gives a stuck shell its own grace to exit after
        // the deadline. Whichever answers first is the answer; the other is
        // left to finish on its own, unheard.
        let answer: [String]? = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task.detached(priority: .userInitiated) {
                let result = await BoundedProcess.run(
                    shell,
                    ["-l", "-i", "-c", "printf '\\n\(marker)%s\\n' \"$PATH\""],
                    environment: environment,
                    deadline: deadline,
                    outputCeiling: 256 * 1024
                )
                guard case .success(let data) = result else { return once.resume(nil) }
                once.resume(parse(String(decoding: data, as: UTF8.self)))
            }
            Task.detached {
                try? await Task.sleep(for: .seconds(deadline + 0.5))
                once.resume(nil)
            }
        }
        guard let answer, !answer.isEmpty else { return inherited }
        // The shell's own first; anything Vigía was started with after it.
        return answer + inherited.filter { !answer.contains($0) }
    }

    /// The shell to ask: an absolute path to a program that exists. zsh when
    /// there is no `SHELL`, which is macOS's default.
    static func shell(from value: String?, exists: (String) -> Bool = FileManager.default.isExecutableFile) -> URL? {
        let path = value.flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "/bin/zsh"
        return exists(path) ? URL(fileURLWithPath: path) : nil
    }

    /// The `PATH` out of whatever the shell printed. Its rc files may print
    /// too — a greeting, a warning — so only the line after the marker counts.
    static func parse(_ output: String) -> [String]? {
        guard let line = output.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix(marker) }) else {
            return nil
        }
        let value = folders(in: String(line.dropFirst(marker.count)))
        return value.isEmpty ? nil : value
    }

    /// `a:b:c` as folders, without blanks, relative entries or repeats.
    static func folders(in path: String?) -> [String] {
        var seen: Set<String> = []
        return (path ?? "").split(separator: ":").map(String.init).filter {
            $0.hasPrefix("/") && seen.insert($0).inserted
        }
    }
}

/// A continuation two racers may both try to resume; the first one does.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
