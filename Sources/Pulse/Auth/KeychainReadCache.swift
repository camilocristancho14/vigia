import Foundation

/// What Vigía has already been handed from another app's keychain item, kept
/// so macOS does not have to be asked again.
///
/// **Why this exists.** The dialog macOS raises for another app's item offers
/// "Always Allow", "Deny" and "Allow" — and "Allow" grants exactly *one* read.
/// Every refresh pass read the item again, so somebody who pressed "Allow"
/// got the same dialog back on the next pass, and the next, until they gave
/// in and pressed "Always Allow". The buttons are the system's and cannot be
/// changed; what can be changed is how often the question is asked. So the
/// first answer is remembered: in memory for the session, and sealed with
/// `LocalSecrets` in Vigía's own folder for the next launch. "Allow" is then
/// enough, once.
///
/// Callers drop an entry with `forget` when what it holds stops working (an
/// expired or refused token), which is the only time the item is read again.
enum KeychainReadCache {
    private static let purpose = "keychain-read-cache"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var memory: [String: Data]?

    static var file: URL { PulseStorage.directory.appending(path: "keychain-cache.dat") }

    /// The remembered value for `key`, or the result of `read` — which is the
    /// call that can raise the prompt — remembered when it produced one.
    static func value(for key: String, read: () -> Data?) -> Data? {
        if let cached = cached(key) { return cached }
        guard let fresh = read() else { return nil }
        store(fresh, for: key)
        return fresh
    }

    static func cached(_ key: String) -> Data? {
        lock.withLock { loaded()[key] }
    }

    static func store(_ value: Data, for key: String) {
        lock.withLock {
            var entries = loaded()
            guard entries[key] != value else { return }
            entries[key] = value
            memory = entries
            persist(entries)
        }
    }

    static func forget(_ key: String) {
        lock.withLock {
            var entries = loaded()
            guard entries.removeValue(forKey: key) != nil else { return }
            memory = entries
            persist(entries)
        }
    }

    // MARK: - Storage. Called with `lock` held.

    private static func loaded() -> [String: Data] {
        if let memory { return memory }
        let entries = (try? Data(contentsOf: file))
            .flatMap { LocalSecrets.open($0, purpose: purpose) }
            .flatMap { try? PropertyListDecoder().decode([String: Data].self, from: $0) }
            ?? [:]
        memory = entries
        return entries
    }

    private static func persist(_ entries: [String: Data]) {
        guard
            let plain = try? PropertyListEncoder().encode(entries),
            let sealed = LocalSecrets.seal(plain, purpose: purpose)
        else { return }
        _ = LocalSecrets.write(sealed, to: file)
    }
}
