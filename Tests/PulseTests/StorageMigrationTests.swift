import Foundation
import Testing
@testable import Pulse

/// Carrying `Application Support/Pulse` over to `Application Support/Vigia`.
/// Every case runs in its own temporary folder, never the user's Library.
@Suite("Storage folder migration")
struct StorageMigrationTests {
    private let base: URL
    private var legacy: URL { base.appending(path: "Pulse") }
    private var current: URL { base.appending(path: "Vigia") }

    init() throws {
        base = FileManager.default.temporaryDirectory.appending(path: "VigiaStorageMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    private func read(_ file: URL) -> String? {
        (try? Data(contentsOf: file)).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test("The default folder is Vigia's")
    func folderName() {
        #expect(PulseStorage.directory.lastPathComponent == "Vigia")
        #expect(PulseStorage.directory.deletingLastPathComponent() == URL.applicationSupportDirectory)
    }

    @Test("Only the old folder: it is renamed, contents and all")
    func moves() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try write("keys", to: legacy.appending(path: "keys.dat"))
        try write("ext", to: legacy.appending(path: "Extensions/acme/run"))

        #expect(PulseStorage.migrateIfNeeded(in: base) == .moved)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(read(current.appending(path: "keys.dat")) == "keys")
        #expect(read(current.appending(path: "Extensions/acme/run")) == "ext")

        // Once done, running again changes nothing.
        #expect(PulseStorage.migrateIfNeeded(in: base) == .none)
        #expect(read(current.appending(path: "keys.dat")) == "keys")
    }

    @Test("Both folders: Vigia's is used and the old one is left exactly as it was")
    func keepsBoth() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try write("old", to: legacy.appending(path: "keys.dat"))
        try write("new", to: current.appending(path: "keys.dat"))

        #expect(PulseStorage.migrateIfNeeded(in: base) == .keptBoth)
        #expect(read(legacy.appending(path: "keys.dat")) == "old")
        #expect(read(current.appending(path: "keys.dat")) == "new")
    }

    @Test("Neither folder, or only the new one: nothing happens")
    func nothingToDo() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(PulseStorage.migrateIfNeeded(in: base) == .none)
        #expect(!FileManager.default.fileExists(atPath: current.path))

        try write("new", to: current.appending(path: "keys.dat"))
        #expect(PulseStorage.migrateIfNeeded(in: base) == .none)
        #expect(read(current.appending(path: "keys.dat")) == "new")
    }

    @Test("A file, not a folder, called Pulse is not moved")
    func ignoresPlainFile() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try write("not a folder", to: legacy)
        #expect(PulseStorage.migrateIfNeeded(in: base) == .none)
        #expect(read(legacy) == "not a folder")
        #expect(!FileManager.default.fileExists(atPath: current.path))
    }

    @Test("A dangling link where Vigia's folder would go is not overwritten")
    func respectsDanglingLink() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try write("old", to: legacy.appending(path: "keys.dat"))
        try FileManager.default.createSymbolicLink(
            atPath: current.path, withDestinationPath: base.appending(path: "nowhere").path
        )
        #expect(PulseStorage.migrateIfNeeded(in: base) == .keptBoth)
        #expect(read(legacy.appending(path: "keys.dat")) == "old")
    }
}
