import Foundation
import Testing
@testable import Pulse

@Suite("Provider readiness")
struct ProviderReadinessTests {
    private let home = URL(fileURLWithPath: "/synthetic-home")

    /// A Mac described by what is on it. Nothing here touches the disk: every
    /// path below is made up, and the probe only answers from these sets.
    private func probe(
        files: [String] = [],
        executables: [String] = [],
        folders: [String: [String]] = [:],
        keychain: Set<String> = [],
        path: [String] = ["/usr/bin", "/bin"]
    ) -> DiscoveryProbe {
        func absolute(_ path: String) -> String {
            path.hasPrefix("/") ? path : home.appending(path: path).path
        }
        let present = Set(files.map(absolute)).union(executables.map(absolute))
        let runnable = Set(executables.map(absolute))
        let listed = Dictionary(uniqueKeysWithValues: folders.map { (absolute($0.key), $0.value) })
        return DiscoveryProbe(
            home: home,
            exists: { present.contains($0) },
            list: { listed[$0] ?? [] },
            hasKeychainItem: { keychain.contains($0) },
            searchPath: path,
            isExecutable: { runnable.contains($0) }
        )
    }

    @Test("A saved login is ready; a folder or a command alone is only installed")
    func loginOrInstalled() {
        let found = Provider.readiness(on: probe(
            files: [".codex/auth.json", ".grok/auth.json", ".gemini/oauth_creds.json", ".commandcode/auth.json", ".factory"],
            executables: ["/opt/homebrew/bin/amp"]
        ))
        #expect(found[.codex] == .ready)
        #expect(found[.grok] == .ready)
        #expect(found[.gemini] == .ready)
        #expect(found[.commandCode] == .ready)
        // A key-only service is never ready from what is on disk.
        #expect(found[.factory] == .installed)
        #expect(found[.amp] == .installed)
        #expect(found[.claudeCode] == nil)
        #expect(found[.deepSeek] == nil)
    }

    @Test("Claude Code is ready from its keychain item, without reading it")
    func claudeKeychain() {
        #expect(Provider.claudeCode.readiness(on: probe(files: [".claude"])) == .installed)
        #expect(Provider.claudeCode.readiness(on: probe(
            files: [".claude"], keychain: ["Claude Code-credentials"]
        )) == .ready)
        #expect(Provider.claudeCode.readiness(on: probe(files: [".claude/.credentials.json"])) == .ready)
        // Its CLI on the login shell's PATH is enough to say it is installed.
        #expect(Provider.claudeCode.readiness(on: probe(
            executables: ["/Users/someone/.custom/bin/claude"], path: ["/Users/someone/.custom/bin"]
        )) == .installed)
    }

    @Test("A login only its own program can read needs that program")
    func loginNeedsItsProgram() {
        let token = ".gemini/jetski-standalone-oauth-token"
        #expect(Provider.antigravity.readiness(on: probe(files: [token])) == .installed)
        #expect(Provider.antigravity.readiness(on: probe(files: [token], executables: [".local/bin/agy"])) == .ready)

        let kiro = "Library/Application Support/kiro-cli/data.sqlite3"
        #expect(Provider.kiro.readiness(on: probe(files: [kiro])) == .installed)
        #expect(Provider.kiro.readiness(on: probe(files: [kiro], executables: ["/usr/local/bin/kiro-cli"])) == .ready)
    }

    @Test("Grok Bot needs its own app as well as Cursor's login")
    func grokBotNeedsItsApp() {
        let cursor = "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        let only = Provider.readiness(on: probe(files: [cursor]))
        #expect(only[.cursor] == .ready)
        #expect(only[.grokBot] == nil)
        #expect(Provider.grokBot.readiness(on: probe(files: [cursor, "/Applications/Grok Bot.app"])) == .ready)
    }

    @Test("OpenCode's shared auth file is a hint, not an OpenCode Go key")
    func openCodeIsOnlyInstalled() {
        #expect(Provider.openCodeGo.readiness(on: probe(files: [".local/share/opencode/auth.json"])) == .installed)
        #expect(!Provider.openCodeGo.canBeReadyWithoutSetup)
    }

    @Test("JetBrains AI is ready once an IDE has saved its quota")
    func jetBrainsQuota() {
        let root = "Library/Application Support/JetBrains"
        let folders = [root: ["Toolbox", "PyCharm2025.2"]]
        #expect(Provider.jetBrainsAI.readiness(on: probe(files: [root], folders: folders)) == .installed)
        #expect(Provider.jetBrainsAI.readiness(on: probe(
            files: [root, "\(root)/PyCharm2025.2/options/AIAssistantQuotaManager2.xml"], folders: folders
        )) == .ready)
    }

    @Test("Commands are found in the usual folders and the Node managers' versions")
    func commandLookup() {
        let nvm = ".nvm/versions/node"
        let found = probe(
            executables: ["\(nvm)/v22.1.0/bin/gemini", ".grok/bin/grok"],
            folders: [nvm: ["v20.0.0", "v22.1.0"]]
        )
        #expect(found.hasCommand("gemini"))
        #expect(found.hasCommand("grok"))
        #expect(!found.hasCommand("codex"))
    }

    @Test("The login shell's PATH is read past whatever its rc files print")
    func shellPathParsing() {
        let output = "Welcome back!\nzsh: no job control\n\n__VIGIA_PATH__/a/bin:/b/bin:relative:/a/bin:\n"
        #expect(LoginShellPath.parse(output) == ["/a/bin", "/b/bin"])
        #expect(LoginShellPath.parse("nothing useful") == nil)
        #expect(LoginShellPath.parse("__VIGIA_PATH__\n") == nil)
        #expect(LoginShellPath.folders(in: nil).isEmpty)
        #expect(LoginShellPath.shell(from: "/bin/fish", exists: { _ in false }) == nil)
        #expect(LoginShellPath.shell(from: "fish", exists: { $0 == "/bin/zsh" })?.path == "/bin/zsh")
        #expect(LoginShellPath.shell(from: "/opt/homebrew/bin/fish", exists: { _ in true })?.path == "/opt/homebrew/bin/fish")
    }

    /// A stand-in shell: a script that ignores its arguments.
    private func script(_ body: String) throws -> (path: String, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vigia-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "shell")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return (file.path, folder)
    }

    @Test("The login shell's PATH comes first, ahead of Vigía's own")
    func shellAnswers() async throws {
        let shell = try script("echo 'Welcome back'; printf '\\n__VIGIA_PATH__/s/bin:/x/bin\\n'")
        defer { try? FileManager.default.removeItem(at: shell.folder) }
        let folders = await LoginShellPath.resolve(deadline: 5, shell: shell.path, fallback: "/x/bin:/y/bin")
        #expect(folders == ["/s/bin", "/x/bin", "/y/bin"])
    }

    @Test("A shell that never answers costs the deadline, not a hang")
    func shellDeadline() async throws {
        let shell = try script("sleep 30")
        defer { try? FileManager.default.removeItem(at: shell.folder) }
        let start = Date()
        let folders = await LoginShellPath.resolve(deadline: 0.3, shell: shell.path, fallback: "/x/bin")
        // The deadline and its half-second of grace, with room for a busy CI
        // runner to schedule the subprocess and deliver its cancellation.
        #expect(Date().timeIntervalSince(start) < 12)
        #expect(folders == ["/x/bin"])
        // One that cannot be started at all falls back at once.
        #expect(await LoginShellPath.resolve(shell: "/nonexistent/shell", fallback: "/x/bin") == ["/x/bin"])
    }

    @Test("The chooser ticks what was found on a first choice, and only ready ones later")
    func chooserPreselection() {
        let all: Set<Provider> = [.claudeCode, .codex, .amp, .deepSeek]
        let detected: Set<Provider> = [.claudeCode, .codex, .amp]
        let ready: Set<Provider> = [.codex]
        #expect(ProviderSetupMode.initial.preselected(from: all, detected: detected, ready: ready)
            == [.claudeCode, .codex, .amp])
        #expect(ProviderSetupMode.newlyDetected.preselected(from: all, detected: detected, ready: ready) == [.codex])
        #expect(ProviderSetupMode.addMore.preselected(from: [.amp], detected: detected, ready: ready).isEmpty)
    }

    @Test("The welcome window's sign-in step matches the ring's remedy")
    func setupRemedies() {
        #expect(ConnectionRemedy.forSetup(of: .claudeCode) == .copyCommand("claude auth login"))
        #expect(ConnectionRemedy.forSetup(of: .codex) == .copyCommand("codex login"))
        #expect(ConnectionRemedy.forSetup(of: .kiro) == .copyCommand("kiro-cli login"))
        #expect(ConnectionRemedy.forSetup(of: .cursor) == .openApp("Cursor"))
        #expect(ConnectionRemedy.forSetup(of: .gemini) == .help)
        #expect(ConnectionRemedy.forSetup(of: .deepSeek) == nil)
    }
}
