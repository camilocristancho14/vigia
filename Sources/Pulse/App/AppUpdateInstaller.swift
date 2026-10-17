// Installing a newer Vigía from inside Vigía.
import Darwin
import Foundation

/// Replaces the running app with the release's `Vigia.zip`.
///
/// **Why in-app at all.** Vigía is signed ad hoc and not notarized, so every
/// copy downloaded with a browser is quarantined, and Gatekeeper stops it with
/// "Apple could not verify…" until the person finds "Open Anyway" in System
/// Settings — on every single update. A file Vigía downloads itself carries no
/// quarantine flag (and any that ditto might carry over is taken off), so
/// after the first install there is nothing for Gatekeeper to ask about.
///
/// **Nothing is touched until everything has checked out.** The order is:
///
/// 1. Download the zip into a fresh temporary folder.
/// 2. Unpack it with `ditto`, the tool that packed it.
/// 3. Check the app inside: bundle id `com.vigia.mac`, the version the release
///    says it is, an executable where its `Info.plist` says, a signature that
///    verifies. A wrong file is refused here, not after it has replaced
///    anything.
/// 4. Copy it beside the installed app under a hidden name. This is the step
///    that needs write access to `/Applications`, and the one that would fail
///    on a full disk — both while the old app is still running and can say so.
/// 5. Hand the swap to a small detached shell script and quit. The script waits
///    for this process to be gone, then renames old → backup and staged → the
///    app's own path; if the second rename fails it puts the backup back. Two
///    renames on one volume, so there is no moment with half an app, and no
///    path through it ends with no app.
/// 6. The script opens the app at its usual path, which is now the new one.
///
/// Any failure before step 5 leaves the installed app exactly as it was, and
/// every failure is offered the release page as the way round it.
enum AppUpdateInstaller {
    static let bundleIdentifier = "com.vigia.mac"

    enum Failure: Error, Equatable, Sendable {
        case download
        /// The archive did not hold the app it should: wrong id, wrong
        /// version, no executable, a signature that does not verify.
        case invalidArchive
        /// Where the app is cannot be written to: a disk image, a translocated
        /// copy, a folder this user does not own.
        case notReplaceable
        case couldNotLaunch

        var message: String {
            switch self {
            case .download: .localized("Couldn't download the update.")
            case .invalidArchive: .localized("The downloaded update didn't check out, so nothing was changed.")
            case .notReplaceable: .localized("Vigía can't replace itself where it is. Move it to Applications, or download the update from the release page.")
            case .couldNotLaunch: .localized("Couldn't start the installer, so nothing was changed.")
            }
        }
    }

    /// Everything the swap script needs, all decided before the app quits.
    struct Plan: Equatable, Sendable {
        /// The temporary folder: zip, unpacked app, the script itself.
        let work: URL
        /// The new app, already copied beside the old one.
        let staged: URL
        /// The installed app's path, which the new app ends up at.
        let target: URL
        /// Where the old app waits until the new one is in place.
        let backup: URL
    }

    // MARK: - Pure parts, tested

    /// Why the app at `installed` cannot be replaced from inside it, or nil.
    ///
    /// A translocated app is a read-only copy macOS made because the original
    /// was opened straight from Downloads with its quarantine flag on;
    /// replacing it would replace nothing anybody can find again.
    static func blocker(installed: URL, parentIsWritable: Bool) -> Failure? {
        guard installed.pathExtension == "app" else { return .notReplaceable }
        if installed.path.contains("/AppTranslocation/") { return .notReplaceable }
        return parentIsWritable ? nil : .notReplaceable
    }

    /// The app in an unpacked archive: `Vigia.app` by name, or the only `.app`
    /// there is. Two unrelated apps is not a guess worth making.
    static func appBundle(among names: [String]) -> String? {
        if names.contains("Vigia.app") { return "Vigia.app" }
        let apps = names.filter { $0.hasSuffix(".app") && !$0.hasPrefix(".") }
        return apps.count == 1 ? apps[0] : nil
    }

    /// Whether an unpacked app's `Info.plist` is the release it claims to be.
    /// The version is compared as numbers, so a plist saying "0.9" passes for
    /// a tag "v0.9.0" — they are one version.
    static func isExpected(info: [String: Any]?, version: String) -> Bool {
        guard let info,
              info["CFBundleIdentifier"] as? String == bundleIdentifier,
              let found = info["CFBundleShortVersionString"] as? String,
              AppUpdate.components(found) != nil
        else { return false }
        return !AppUpdate.isNewer(found, than: version) && !AppUpdate.isNewer(version, than: found)
    }

    /// One shell word, whatever is in it: single quotes, with any single
    /// quote inside closed, escaped and reopened.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The script that swaps the apps once `pid` has exited.
    ///
    /// Waits two minutes at most. If Vigía is somehow still running by then —
    /// a quit somebody cancelled — it takes the staged copy away and leaves
    /// everything else alone, rather than renaming an app out from under a
    /// running process.
    static func script(for plan: Plan, waitingFor pid: Int32) -> String {
        let target = shellQuoted(plan.target.path)
        let staged = shellQuoted(plan.staged.path)
        let backup = shellQuoted(plan.backup.path)
        let work = shellQuoted(plan.work.path)
        return """
        #!/bin/sh
        # Vigía's updater. Swaps the installed app for the one beside it, once
        # Vigía has quit, and reopens it. Never leaves the path without an app.
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        target=\(target)
        staged=\(staged)
        backup=\(backup)
        work=\(work)
        i=0
        while kill -0 \(pid) 2>/dev/null; do
          i=$((i + 1))
          if [ "$i" -ge 1200 ]; then
            rm -rf "$staged" "$work"
            exit 1
          fi
          sleep 0.1
        done
        if [ -d "$staged" ] && mv "$target" "$backup"; then
          if mv "$staged" "$target"; then
            rm -rf "$backup"
          else
            mv "$backup" "$target"
            rm -rf "$staged"
          fi
        else
          rm -rf "$staged"
        fi
        rm -rf "$work"
        open "$target"

        """
    }

    // MARK: - Steps

    /// Steps 1–4. Nothing outside the temporary folder and the hidden staged
    /// copy is written; on failure both are removed.
    static func prepare(archive: URL, expectedVersion: String, installed: URL) async -> Result<Plan, Failure> {
        let files = FileManager.default
        let parent = installed.deletingLastPathComponent()
        if let blocker = blocker(installed: installed, parentIsWritable: files.isWritableFile(atPath: parent.path)) {
            return .failure(blocker)
        }

        let token = UUID().uuidString
        let work = files.temporaryDirectory.appendingPathComponent("vigia-update-\(token)", isDirectory: true)
        let staged = parent.appendingPathComponent(".Vigia-update-\(token).app", isDirectory: true)
        let backup = parent.appendingPathComponent(".Vigia-previous-\(token).app", isDirectory: true)
        let plan = Plan(work: work, staged: staged, target: installed, backup: backup)

        func fail(_ failure: Failure) -> Result<Plan, Failure> {
            discard(plan)
            return .failure(failure)
        }

        do {
            try files.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            return fail(.download)
        }

        // 1. Download.
        let zip = work.appendingPathComponent("Vigia.zip")
        var request = URLRequest(url: archive, timeoutInterval: 120)
        request.setValue("Vigia", forHTTPHeaderField: "User-Agent")
        guard let (downloaded, response) = try? await NetworkSession.shared.download(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              (try? files.moveItem(at: downloaded, to: zip)) != nil
        else { return fail(.download) }

        // 2. Unpack.
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        guard case .success = await run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path], deadline: 120),
              let names = try? files.contentsOfDirectory(atPath: unpacked.path),
              let name = appBundle(among: names)
        else { return fail(.invalidArchive) }
        let app = unpacked.appendingPathComponent(name, isDirectory: true)

        // 3. Check it.
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard isExpected(info: info, version: expectedVersion),
              let executable = info?["CFBundleExecutable"] as? String,
              files.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/\(executable)").path),
              case .success = await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], deadline: 60)
        else { return fail(.invalidArchive) }
        // Its status is not read: with nothing to remove, xattr reports that as
        // an error, and an absent flag is the outcome wanted either way.
        _ = await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path], deadline: 30)

        // 4. Stage it beside the installed app, on the same volume, so the
        // swap is two renames.
        guard case .success = await run("/usr/bin/ditto", [app.path, staged.path], deadline: 120) else {
            return fail(.notReplaceable)
        }
        return .success(plan)
    }

    /// Step 5: writes the script and starts it in a session of its own, so it
    /// outlives this process however the system ends it.
    static func launch(_ plan: Plan, waitingFor pid: Int32) throws {
        let scriptURL = plan.work.appendingPathComponent("install.sh")
        try script(for: plan, waitingFor: pid).write(to: scriptURL, atomically: true, encoding: .utf8)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Its own session, out of the app's process group; and none of the
        // app's open descriptors, which it has no use for.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

        let arguments = ["/bin/sh", scriptURL.path]
        let environment = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin"]
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var child: pid_t = 0
        let status = posix_spawn(&child, "/bin/sh", &actions, &attributes, &argv, &envp)
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO) }
    }

    /// Takes away what `prepare` made. Never the installed app.
    static func discard(_ plan: Plan) {
        let files = FileManager.default
        try? files.removeItem(at: plan.staged)
        try? files.removeItem(at: plan.work)
    }

    private static func run(_ tool: String, _ arguments: [String], deadline: TimeInterval) async -> Result<Data, BoundedProcess.Failure> {
        await BoundedProcess.run(
            URL(fileURLWithPath: tool), arguments,
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            deadline: deadline,
            outputCeiling: 64 * 1024
        )
    }
}
