// by cipher.org.uk
import Foundation

/// Token storage for platforms without the macOS Keychain (Linux): a JSON
/// object `{ identity: token }` in a file only the current user can read.
///
/// This is weaker than the Keychain (the tokens are not encrypted at rest), so
/// it is only used where no system keychain API is available. The file lives at
/// `<Application Support>/KarmaPro/PullRequestTokens.json` with mode 0600, in a
/// folder with mode 0700.
final class FilePRTokenStorage: PRTokenStorage {
    private let fileURL: URL
    private let lock = NSLock()
    private var cache: [String: String]?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("KarmaPro", isDirectory: true)
            .appendingPathComponent("PullRequestTokens.json")
    }

    func token(identity: String, prompt: Bool) -> String? {
        lock.lock(); defer { lock.unlock() }
        return load()[identity]
    }

    func setToken(_ token: String, identity: String) throws {
        lock.lock(); defer { lock.unlock() }
        var tokens = load()
        tokens[identity] = token
        try save(tokens)
    }

    func deleteToken(identity: String) throws {
        lock.lock(); defer { lock.unlock() }
        var tokens = load()
        guard tokens.removeValue(forKey: identity) != nil else { return }
        try save(tokens)
    }

    func invalidateSessionCache() {
        lock.lock(); defer { lock.unlock() }
        cache = nil
    }

    // MARK: - File access (callers hold the lock)

    private func load() -> [String: String] {
        if let cache { return cache }
        let tokens = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        cache = tokens
        return tokens
    }

    private func save(_ tokens: [String: String]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        let data = try encoder.encode(tokens)
        // Create the file with mode 0600 from the start (never world-readable,
        // not even briefly), then move it into place.
        let temp = directory.appendingPathComponent(".tokens-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temp.path, contents: data,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if rename(temp.path, fileURL.path) != 0 {
            try? FileManager.default.removeItem(at: temp)
            throw CocoaError(.fileWriteUnknown)
        }
        cache = tokens
    }
}
