import Foundation
import Testing
@testable import Pulse

/// The update check and the in-app install: everything about them that can be
/// decided without a network or a real `/Applications`.
@Suite("App update")
struct AppUpdateTests {
    // MARK: Versions

    @Test("Tags read as versions with or without the v")
    func components() {
        #expect(AppUpdate.components("v0.9.0") == [0, 9, 0])
        #expect(AppUpdate.components("0.10.2") == [0, 10, 2])
        #expect(AppUpdate.components(" V1 ") == [1])
        #expect(AppUpdate.components("v0.9.0-beta") == nil)
        #expect(AppUpdate.components("0..1") == nil)
        #expect(AppUpdate.components("") == nil)
        #expect(AppUpdate.components("main") == nil)
    }

    @Test("Newer is numeric, not alphabetical, and zero-padded")
    func comparison() {
        #expect(AppUpdate.isNewer("0.9.0", than: "0.8.0"))
        #expect(AppUpdate.isNewer("v0.10.0", than: "0.9.9"))
        #expect(AppUpdate.isNewer("1.0", than: "0.99.99"))
        #expect(AppUpdate.isNewer("0.8.1", than: "0.8"))
        #expect(!AppUpdate.isNewer("0.8.0", than: "0.8"))
        #expect(!AppUpdate.isNewer("0.8.0", than: "0.8.0"))
        #expect(!AppUpdate.isNewer("0.7.9", than: "0.8.0"))
        // Unreadable on either side is never offered.
        #expect(!AppUpdate.isNewer("nightly", than: "0.8.0"))
        #expect(!AppUpdate.isNewer("0.9.0", than: "dev"))
    }

    @Test("A check is due once a day, or when the clock went backwards")
    func due() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(AppUpdate.isDue(lastCheck: nil, now: now))
        #expect(!AppUpdate.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        #expect(AppUpdate.isDue(lastCheck: now.addingTimeInterval(-AppUpdate.checkInterval), now: now))
        #expect(AppUpdate.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }

    // MARK: Feed

    private func reply(tag: String, assets: [String], draft: Bool = false, prerelease: Bool = false) -> Data {
        let list = assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://github.com/camilocristancho14/vigia/releases/download/\#(tag)/\#($0)"}"#
        }.joined(separator: ",")
        return Data(#"""
        {"tag_name":"\#(tag)","html_url":"https://github.com/camilocristancho14/vigia/releases/tag/\#(tag)",
         "draft":\#(draft),"prerelease":\#(prerelease),"assets":[\#(list)],"body":"ignored"}
        """#.utf8)
    }

    @Test("The latest release is read with its page and its zip")
    func parse() throws {
        let release = try #require(AppUpdate.parseRelease(reply(tag: "v0.9.0", assets: ["Vigia.dmg", "Vigia.zip"])))
        #expect(release.version == "0.9.0")
        #expect(release.page.absoluteString == "https://github.com/camilocristancho14/vigia/releases/tag/v0.9.0")
        #expect(release.archive?.lastPathComponent == "Vigia.zip")
    }

    @Test("A release without a zip is still a release, with nothing to install")
    func parseWithoutZip() throws {
        let release = try #require(AppUpdate.parseRelease(reply(tag: "v1.2", assets: ["Vigia.dmg"])))
        #expect(release.version == "1.2")
        #expect(release.archive == nil)
    }

    @Test("Drafts, pre-releases, odd tags and error bodies are not releases")
    func parseRefusals() {
        #expect(AppUpdate.parseRelease(reply(tag: "v0.9.0", assets: ["Vigia.zip"], draft: true)) == nil)
        #expect(AppUpdate.parseRelease(reply(tag: "v0.9.0", assets: ["Vigia.zip"], prerelease: true)) == nil)
        #expect(AppUpdate.parseRelease(reply(tag: "v0.9.0-rc1", assets: ["Vigia.zip"])) == nil)
        #expect(AppUpdate.parseRelease(Data(#"{"message":"Not Found"}"#.utf8)) == nil)
        #expect(AppUpdate.parseRelease(Data("<html>".utf8)) == nil)
    }

    @Test("The zip is picked by name, never the disk image")
    func assetSelection() {
        let url = { (name: String) in URL(string: "https://example.com/\(name)")! }
        let pick = { (names: [String]) in AppUpdate.archive(among: names.map { ($0, url($0)) })?.lastPathComponent }
        #expect(pick(["Vigia.dmg", "Other.zip", "Vigia.zip"]) == "Vigia.zip")
        #expect(pick(["Vigia.dmg", "Vigia-0.9.0.zip"]) == "Vigia-0.9.0.zip")
        #expect(pick(["Vigia.dmg"]) == nil)
        #expect(pick(["Source.zip"]) == nil)
        #expect(pick([]) == nil)
    }

    // MARK: Install

    @Test("Only the Vigía bundle at the release's version is accepted")
    func validation() {
        let good: [String: Any] = ["CFBundleIdentifier": "com.vigia.mac", "CFBundleShortVersionString": "0.9.0"]
        #expect(AppUpdateInstaller.isExpected(info: good, version: "0.9.0"))
        #expect(AppUpdateInstaller.isExpected(info: good, version: "0.9"))
        #expect(!AppUpdateInstaller.isExpected(info: good, version: "0.9.1"))
        #expect(!AppUpdateInstaller.isExpected(info: nil, version: "0.9.0"))
        var other = good
        other["CFBundleIdentifier"] = "com.example.vigia"
        #expect(!AppUpdateInstaller.isExpected(info: other, version: "0.9.0"))
        var noVersion = good
        noVersion["CFBundleShortVersionString"] = nil
        #expect(!AppUpdateInstaller.isExpected(info: noVersion, version: "0.9.0"))
    }

    @Test("The unpacked app is Vigia.app, or the only app there")
    func appBundle() {
        #expect(AppUpdateInstaller.appBundle(among: ["__MACOSX", "Vigia.app"]) == "Vigia.app")
        #expect(AppUpdateInstaller.appBundle(among: ["Vigía.app"]) == "Vigía.app")
        #expect(AppUpdateInstaller.appBundle(among: ["A.app", "B.app"]) == nil)
        #expect(AppUpdateInstaller.appBundle(among: ["readme.txt"]) == nil)
    }

    @Test("A copy that can't be written to, or was translocated, is not replaced")
    func blockers() {
        let installed = URL(fileURLWithPath: "/Applications/Vigia.app")
        #expect(AppUpdateInstaller.blocker(installed: installed, parentIsWritable: true) == nil)
        #expect(AppUpdateInstaller.blocker(installed: installed, parentIsWritable: false) == .notReplaceable)
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Vigia.app")
        #expect(AppUpdateInstaller.blocker(installed: translocated, parentIsWritable: true) == .notReplaceable)
        let bare = URL(fileURLWithPath: "/Users/me/vigia/.build/debug/Pulse")
        #expect(AppUpdateInstaller.blocker(installed: bare, parentIsWritable: true) == .notReplaceable)
    }

    @Test("Paths are quoted as one shell word, quotes and all")
    func quoting() {
        #expect(AppUpdateInstaller.shellQuoted("/Applications/Vigia.app") == "'/Applications/Vigia.app'")
        #expect(AppUpdateInstaller.shellQuoted("/Users/o'neil/Apps/Vigia.app") == #"'/Users/o'\''neil/Apps/Vigia.app'"#)
        #expect(AppUpdateInstaller.shellQuoted("$(rm -rf ~)") == "'$(rm -rf ~)'")
    }

    private let plan = AppUpdateInstaller.Plan(
        work: URL(fileURLWithPath: "/tmp/vigia-update-1"),
        staged: URL(fileURLWithPath: "/Applications/.Vigia-update-1.app"),
        target: URL(fileURLWithPath: "/Applications/Vigia.app"),
        backup: URL(fileURLWithPath: "/Applications/.Vigia-previous-1.app")
    )

    @Test("The script waits for the app, swaps by renaming, and reopens it")
    func script() throws {
        let script = AppUpdateInstaller.script(for: plan, waitingFor: 4242)
        #expect(script.hasPrefix("#!/bin/sh\n"))
        #expect(script.contains("target='/Applications/Vigia.app'"))
        #expect(script.contains("staged='/Applications/.Vigia-update-1.app'"))
        #expect(script.contains("while kill -0 4242 2>/dev/null"))
        #expect(script.contains(#"open "$target""#))
        // The old app moves aside before the new one moves in, and comes back
        // if the second move fails.
        let aside = try #require(script.range(of: #"mv "$target" "$backup""#))
        let into = try #require(script.range(of: #"mv "$staged" "$target""#))
        let back = try #require(script.range(of: #"mv "$backup" "$target""#))
        #expect(aside.lowerBound < into.lowerBound)
        #expect(into.lowerBound < back.lowerBound)
        // The installed app is never deleted, only renamed.
        #expect(!script.contains(#"rm -rf "$target""#))
    }

    @Test("The script parses and, run for real, swaps the apps and keeps neither copy behind")
    func scriptRuns() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("vigia-script-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let apps = root.appendingPathComponent("Apps")
        let work = root.appendingPathComponent("work")
        try files.createDirectory(at: apps, withIntermediateDirectories: true)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        let target = apps.appendingPathComponent("Vigia.app")
        let staged = apps.appendingPathComponent(".Vigia-update-t.app")
        try files.createDirectory(at: target, withIntermediateDirectories: true)
        try files.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appendingPathComponent("marker"))
        try Data("new".utf8).write(to: staged.appendingPathComponent("marker"))
        let local = AppUpdateInstaller.Plan(
            work: work, staged: staged, target: target,
            backup: apps.appendingPathComponent(".Vigia-previous-t.app")
        )
        // `open` is the only step with an effect outside the folder; a stub
        // earlier on PATH takes its place. The pid is one that has exited.
        let bin = root.appendingPathComponent("bin")
        try files.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = AppUpdateInstaller.script(for: local, waitingFor: 999_999)
            .replacingOccurrences(of: "PATH=/usr/bin:/bin:/usr/sbin:/sbin", with: "PATH=\(bin.path):/usr/bin:/bin:/usr/sbin:/sbin")
        try "#!/bin/sh\necho \"$1\" > \(AppUpdateInstaller.shellQuoted(root.appendingPathComponent("opened").path))\n"
            .write(to: bin.appendingPathComponent("open"), atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appendingPathComponent("open").path)
        let scriptFile = root.appendingPathComponent("install.sh")
        try script.write(to: scriptFile, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptFile.path]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8) == "new")
        #expect(try files.contentsOfDirectory(atPath: apps.path) == ["Vigia.app"])
        #expect(!files.fileExists(atPath: work.path))
        #expect(try String(contentsOf: root.appendingPathComponent("opened"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) == target.path)
    }
}
