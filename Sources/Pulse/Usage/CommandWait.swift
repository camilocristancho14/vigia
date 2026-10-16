import Foundation

/// A turn that is waiting on a long command rather than on the model: a test
/// suite, a build, or any shell command that has been running a while.
///
/// **Why it is its own state.** While the model thinks, the account is
/// spending tokens; while `manage.py test` runs for four minutes it is not,
/// and yet the turn is still in flight. Shown as plain work the two look the
/// same, so the mark can't say which one you are paying for. These labels
/// say it: «Probando…» for tests, «Compilando…» for builds, «Esperando
/// comando…» for any other command past `threshold`.
///
/// **Only a category leaves a machine.** The command is read where it runs —
/// the transcript on this Mac, the hook on another — and classified there.
/// The hook sends `"kind": "test"` or `"build"` and never the command itself.
/// `scripts/vigia-notify.sh` carries the same rules in Bash, checked against
/// the same table as these (`Tests/PulseTests/Fixtures/command-kinds.tsv`).
///
/// Foundation only, on purpose: the rules can be built and tested anywhere.
enum CommandKind: String, Sendable, Equatable, CaseIterable {
    case test
    case build

    /// The kind a hook named, loosely: nil for anything it does not know,
    /// which is what an older hook (no `kind` at all) sends.
    init?(named name: String?) {
        guard let name = name?.trimmingCharacters(in: .whitespaces).lowercased(), !name.isEmpty else { return nil }
        switch name {
        case "test", "tests", "testing": self = .test
        case "build", "building", "compile": self = .build
        default: return nil
        }
    }
}

enum CommandWait {
    /// How long a shell command may run before the mark stops calling it work
    /// in progress and starts calling it a wait.
    static let threshold: TimeInterval = 20
    /// How long a test run or a build may go without a word before its claim
    /// to be running lapses. Claude Code's Bash tool stops a command at ten
    /// minutes; the margin covers a slow hook or a clock between machines.
    static let longGrace: TimeInterval = 15 * 60

    /// The labels this state shows, as English keys for `String.localized`.
    static let testingLabel = "Testing…"
    static let buildingLabel = "Building…"
    static let waitingLabel = "Waiting on command…"
    static let labels: Set<String> = [testingLabel, buildingLabel, waitingLabel]

    /// Whether a label is one of the waits, whose timer counts from when the
    /// command started rather than from when the turn did.
    static func isWait(_ label: String?) -> Bool { label.map(labels.contains) ?? false }

    /// How long a tool call's claim to be running may outlive the record that
    /// made it: a test or a build gets the long grace, anything else the
    /// ordinary one for what the turn is waiting on.
    static func grace(ordinary: TimeInterval, kind: CommandKind?) -> TimeInterval {
        kind == nil ? ordinary : max(ordinary, longGrace)
    }

    /// The label for a tool call that has been running for `running` seconds.
    /// Shell commands only: anything else is named by `toolLabel`.
    static func label(tool: String, kind: CommandKind?, running: TimeInterval,
                      toolLabel: (String) -> String) -> String {
        guard isShell(tool) else { return toolLabel(tool) }
        switch kind {
        case .test: return testingLabel
        case .build: return buildingLabel
        case nil: return running >= threshold ? waitingLabel : toolLabel(tool)
        }
    }

    /// Claude Code's `Bash`, and what Grok Build and others call theirs.
    static func isShell(_ tool: String) -> Bool {
        ["bash", "shell", "run_command", "run_shell_command", "run_terminal_command", "terminal", "exec_command"]
            .contains(tool.lowercased())
    }

    // MARK: - Classifying a command

    /// What a shell command is, from its text: a test run, a build, or
    /// neither. Compound commands count as their slowest part — `swift build
    /// && swift test` is a test run.
    ///
    /// Each segment (split at `&&`, `||`, `;`, `|`, `&`, newlines) is read
    /// word by word for the first word that decides: a test runner
    /// (`pytest`), a tool with a test or build subcommand (`swift test`,
    /// `npm run build`), or one that never is (`git`, `grep`, `pip install`).
    /// Words nobody knows — `timeout 600`, `uv run`, `docker compose exec web`,
    /// a path to a venv — are stepped over, so wrappers need no list of their
    /// own.
    static func kind(of command: String) -> CommandKind? {
        var found: CommandKind?
        for segment in segments(of: command) {
            switch kind(ofSegment: words(of: segment)) {
            case .test: return .test
            case .build: found = .build
            case nil: continue
            }
        }
        return found
    }

    static func segments(of command: String) -> [String] {
        var text = command.lowercased()
        for separator in ["&&", "||", "\n", ";", "|", "&"] {
            text = text.replacingOccurrences(of: separator, with: "\u{1}")
        }
        return text.split(separator: "\u{1}").map(String.init)
    }

    static func words(of segment: String) -> [String] {
        let stripped = segment.unicodeScalars.map { "\"'`()".unicodeScalars.contains($0) ? " " : Character($0) }
        return String(stripped).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    private enum Verdict { case decided(CommandKind?), skip }

    private static func kind(ofSegment words: [String]) -> CommandKind? {
        var index = 0
        // `FOO=1 BAR=2 pytest`: assignments first.
        while index < words.count, isAssignment(words[index]) { index += 1 }
        while index < words.count {
            if case .decided(let kind) = verdict(words, at: index) { return kind }
            index += 1
        }
        return nil
    }

    private static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        return word[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Programs that only ever read, move or fetch: a test runner named after
    /// one of them is an argument (`grep -r pytest`, `pip install pytest`).
    private static let neverLong: Set<String> = [
        "echo", "printf", "cat", "less", "more", "head", "tail", "grep", "egrep", "rg", "ag", "find", "fd",
        "ls", "tree", "git", "gh", "sed", "awk", "cd", "pwd", "which", "type", "man", "vim", "vi", "nano",
        "code", "open", "cp", "mv", "rm", "mkdir", "touch", "chmod", "pip", "pip3", "brew", "apt", "apt-get",
        "curl", "wget", "jq", "wc", "sort", "diff", "kill", "pkill", "ps", "tee", "xargs", "export", "source",
        "gem"
    ]

    private static let testRunners: Set<String> = [
        "pytest", "py.test", "tox", "nox", "unittest", "jest", "vitest", "mocha", "rspec", "phpunit",
        "ctest", "karma", "ava"
    ]

    private static func verdict(_ words: [String], at index: Int) -> Verdict {
        let word = words[index]
        let program = word.split(separator: "/").last.map(String.init) ?? word
        let rest = Array(words[(index + 1)...])
        let arguments = rest.filter { !$0.hasPrefix("-") }
        let first = arguments.first ?? ""
        let any = { (names: Set<String>) in arguments.contains(where: names.contains) }

        if neverLong.contains(program) { return .decided(nil) }
        if testRunners.contains(program) { return .decided(.test) }
        if program.hasPrefix("python") || program == "py" {
            // `python -c "import pytest"` runs no tests; `python -m pytest` does,
            // and is read on at `pytest`.
            return rest.first == "-c" ? .decided(nil) : .skip
        }

        switch program {
        case "manage.py":
            return .decided(first == "test" ? .test : nil)
        case "playwright":
            return .decided(first == "test" ? .test : nil)
        case "cypress":
            return .decided(first == "run" ? .test : nil)
        case "swift", "go", "dotnet":
            return .decided(first == "test" ? .test : first == "build" ? .build : nil)
        case "cargo":
            return .decided(["test", "nextest"].contains(first) ? .test : first == "build" ? .build : nil)
        case "mix":
            return .decided(first == "test" ? .test : first == "compile" ? .build : nil)
        case "xcodebuild":
            return .decided(any(["test", "test-without-building"]) ? .test : .build)
        case "make", "gmake":
            if any(["test", "tests", "check"]) { return .decided(.test) }
            return .decided(first.isEmpty || any(["build", "all", "release"]) ? .build : nil)
        case "mvn", "mvnw":
            if any(["test", "verify", "integration-test"]) { return .decided(.test) }
            return .decided(any(["package", "install", "compile"]) ? .build : nil)
        case "gradle", "gradlew":
            if arguments.contains(where: { $0 == "check" || $0.hasPrefix("test") || $0.hasSuffix(":test") }) {
                return .decided(.test)
            }
            let builds = arguments.contains { $0.hasPrefix("assemble") || $0 == "build" || $0.hasSuffix(":build") }
            return .decided(builds ? .build : nil)
        case "rake", "rails":
            return .decided(first.hasPrefix("test") || first.hasPrefix("spec") ? .test : nil)
        case "docker", "podman":
            // `docker compose exec web pytest` is read on; a build is a build.
            if first == "build" || (["compose", "buildx", "image"].contains(first) && arguments.dropFirst().first == "build") {
                return .decided(.build)
            }
            return .skip
        case "uv", "poetry", "pipenv", "pdm", "hatch", "rye", "pixi", "bundle", "conda", "mamba":
            // `uv run pytest` is read on; `poetry add pytest` installs one.
            return ["run", "exec"].contains(first) ? .skip : .decided(nil)
        case "tsc", "webpack":
            return .decided(.build)
        case "vite", "next", "nuxt", "astro":
            return .decided(first == "build" ? .build : nil)
        case "npm", "pnpm", "yarn", "bun":
            return packageManager(program, arguments: arguments)
        default:
            // A project's own script: `./scripts/run-tests.sh`, `build.sh`.
            if program.hasSuffix(".sh") {
                if program.contains("test") { return .decided(.test) }
                if program.contains("build") { return .decided(.build) }
            }
            return .skip
        }
    }

    /// `npm test`, `npm run test:e2e`, `yarn build`, `pnpm exec jest`.
    private static func packageManager(_ program: String, arguments: [String]) -> Verdict {
        guard let sub = arguments.first else { return .decided(nil) }
        if ["test", "t", "tst"].contains(sub) { return .decided(.test) }
        // Runs a binary, which is read on: `pnpm exec jest`, `yarn dlx vitest`.
        if ["exec", "dlx", "x"].contains(sub) { return .skip }
        if ["run", "run-script"].contains(sub) {
            return .decided(arguments.dropFirst().first.flatMap(script))
        }
        // `yarn build`, `pnpm test:unit`: Yarn, pnpm and Bun run a script
        // named as the subcommand. npm does not.
        let builtIn: Set<String> = ["install", "i", "add", "ci", "remove", "rm", "uninstall", "update", "up",
                                    "upgrade", "init", "create", "publish", "link", "outdated", "audit", "why",
                                    "info", "view", "list", "ls", "login", "config", "cache", "version", "pack"]
        guard program != "npm", !builtIn.contains(sub) else { return .decided(nil) }
        return .decided(script(sub))
    }

    /// A package.json script, by its name.
    private static func script(_ name: String) -> CommandKind? {
        if ["test", "e2e", "spec", "playwright", "cypress", "jest", "vitest"].contains(where: name.contains) {
            return .test
        }
        if name.hasPrefix("build") || ["compile", "bundle", "dist"].contains(name) { return .build }
        return nil
    }
}
