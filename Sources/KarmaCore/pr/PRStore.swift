// by cipher.org.uk
import Foundation

/// Secret storage for forge API tokens. The PR layer never touches a concrete
/// secret store: each front end installs one in `PRStore.tokenStorage` (the
/// AppKit app uses the macOS Keychain). Without one, no token can be read or
/// saved, so every forge request goes out unauthenticated.
protocol PRTokenStorage {
    func token(identity: String, prompt: Bool) -> String?
    func setToken(_ token: String, identity: String) throws
    func deleteToken(identity: String) throws
    /// Drops anything cached from the current session.
    func invalidateSessionCache()
}

/// Used when the front end installed no secret store.
struct UnavailablePRTokenStorage: PRTokenStorage {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { "No secure token storage is available in this build." }
    }

    func token(identity: String, prompt: Bool) -> String? { nil }
    func setToken(_ token: String, identity: String) throws { throw Unavailable() }
    func deleteToken(identity: String) throws {}
    func invalidateSessionCache() {}
}

/// One saved account. The token itself is never part of this struct — only the
/// identity used to look it up in the Keychain.
struct PRAccount: Codable, Equatable {
    /// Keychain lookup key, e.g. "github|github.com|alice".
    ///
    /// The host is part of it because two accounts can share a provider and a
    /// username label while belonging to different forges — the same person on
    /// github.com and on a GitHub Enterprise install — and without the host the
    /// second one silently replaced the first. Accounts saved by an earlier
    /// build used "provider|username"; `migratedIdentity` repairs those on load
    /// and moves the Keychain entry across, so no saved token is lost.
    var identity: String
    /// Forge provider id, e.g. "github".
    var provider: String
    /// Login or token label the user recognises.
    var username: String
    /// API root, so a self-hosted GitLab account is distinct from gitlab.com.
    var baseURL: String

    var providerName: String {
        switch provider {
        case "gitlab": return "GitLab"
        case "bitbucket": return "Bitbucket"
        case "gitea": return "Gitea / Forgejo"
        default: return "GitHub"
        }
    }

    /// Which saved account (if any) applies to a monitored repo. Public repos
    /// deliberately match nothing so they keep working with no credentials.
    ///
    /// Both sides are put through the same host-to-API-root derivation before
    /// comparing. Comparing the stored strings directly meant an account saved
    /// as "codeberg.org" never matched a repository detected as
    /// "https://codeberg.org/api/v1", so a private Gitea or self-hosted GitLab
    /// repository silently never found its token and every request went out
    /// unauthenticated. 
    func matches(_ repo: MonitoredRepo) -> Bool {
        guard repo.visibility.needsCredentials else { return false }
        guard provider == repo.provider else { return false }
        return normalizedAPIHost == repo.normalizedAPIHost
    }

    /// The provider host this account belongs to, recovered from the stored
    /// baseURL. `https://api.github.com` is github.com, `https://codeberg.org/
    /// api/v1` is codeberg.org, and a saved bare host is taken as-is.
    var normalizedAPIHost: String? { PRHost.apiHost(baseURL) }

    /// The identity this account should have now: provider|host|username.
    ///
    /// Returns the existing identity unchanged when it already carries a host,
    /// so this is safe to run over a freshly saved account.
    var migratedIdentity: String {
        // Only the pre-host form is migrated. Rewriting an identity that already
        // has a host would strand the token: the move in resolveToken only runs
        // while this process remembers the old key.
        guard identity.split(separator: "|").count == 2 else { return identity }
        guard let host = normalizedAPIHost else { return identity }
        return "\(provider)|\(host)|\(username)"
    }
}

/// Accounts plus the app-wide PR preferences, persisted together in
/// Application Support so a relaunch restores the menu exactly as the user
/// left it.
final class PRStore {
    static let shared = PRStore()

    /// Where account tokens live. Installed by the front end before first use
    /// (the AppKit app uses the Keychain); see `PRTokenStorage`.
    var tokenStorage: PRTokenStorage = UnavailablePRTokenStorage()

    private(set) var accounts: [PRAccount] = []
    private(set) var repos: [MonitoredRepo] = []
    var defaultDepth: PRKind.Depth = .changedOnly { didSet { persistUnlessLoading() } }
    var notifyStyle: PRKind.NotifyStyle = .banner { didSet { persistUnlessLoading() } }
    var pollingIntervalMinutes: Int = 15 { didSet { persistUnlessLoading() } }
    /// Master switch. Off by default: a fresh install never calls out to any
    /// forge until the user turns PR monitoring on from the menu.
    ///
    /// Persisted as soon as it changes. It used to be a plain property written
    /// only when some unrelated setting happened to save the file, so switching
    /// monitoring off did not survive a restart and the app came back polling.
    var monitoringEnabled: Bool = false {
        didSet {
            guard monitoringEnabled != oldValue else { return }
            persistUnlessLoading()
            if !monitoringEnabled {
                // Nothing may reach the Keychain while monitoring is off, and
                // nothing is left over from the session that just ended.
                tokenStorage.invalidateSessionCache()
            }
        }
    }
    /// PR fingerprints the user chose to ignore. Keyed by
    /// `repoId#prId@headSHA` so re-opening an ignored PR after new commits
    /// alerts again, which is the behaviour people expect.
    private(set) var ignoredPRs: Set<String> = []

    private let fileURL: URL

    /// Set while `load()` restores saved values, so the `didSet` observers do
    /// not write the file back out half-restored.
    private var isLoading = false

    /// The app's store, in Application Support.
    private convenience init() {
        self.init(fileURL: PRStore.defaultFileURL())
    }

    /// A store kept in `fileURL`. Tests pass a temporary file so they never touch Application Support.
    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("KarmaPro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("PullRequests.json")
    }

    // MARK: - Accounts

    func saveAccount(_ account: PRAccount, token: String) throws {
        var account = account
        account.identity = account.migratedIdentity
        try tokenStorage.setToken(token, identity: account.identity)
        if let index = accounts.firstIndex(where: { $0.identity == account.identity }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        persist()
    }

    /// Re-keys accounts saved before the host joined the identity.
    @discardableResult
    private func migrateAccountIdentities() -> Bool {
        var changed = false
        for index in accounts.indices {
            let old = accounts[index].identity
            let new = accounts[index].migratedIdentity
            guard new != old else { continue }
            legacyIdentityFor[new] = old
            accounts[index].identity = new
            changed = true
        }
        return changed
    }

    /// New identity -> the older identity its Keychain entry may still use.
    private var legacyIdentityFor: [String: String] = [:]

    /// The token for an account, moving a legacy Keychain entry across on the
    /// first read that needs it.
    private func resolveToken(identity: String, prompt: Bool) -> String? {
        if let token = tokenStorage.token(identity: identity, prompt: prompt) { return token }
        guard let old = legacyIdentityFor[identity] else { return nil }
        // Still not found under the current key, so try the one this account was
        // saved under before the host joined its identity.
        guard let legacy = tokenStorage.token(identity: old, prompt: prompt) else { return nil }
        try? tokenStorage.setToken(legacy, identity: identity)
        try? tokenStorage.deleteToken(identity: old)
        legacyIdentityFor.removeValue(forKey: identity)
        return legacy
    }

    /// Saved accounts that can actually authenticate this repository.
    func accounts(for repo: MonitoredRepo) -> [PRAccount] {
        accounts.filter { $0.matches(repo) && $0.normalizedAPIHost == repo.normalizedAPIHost }
    }

    func removeAccount(_ account: PRAccount) throws {
        try tokenStorage.deleteToken(identity: account.identity)
        accounts.removeAll { $0.identity == account.identity }
        persist()
    }

    /// - Parameter prompt: whether this lookup may put a Keychain dialog in
    ///   front of the user. Callers that only display state, or that run in the
    ///   background, pass the monitoring switch so an idle app never asks.
    func token(for repo: MonitoredRepo, prompt: Bool = true) -> String? {
        guard let account = resolvedAccount(for: repo) else { return nil }
        return resolveToken(identity: account.identity, prompt: prompt)
    }

    /// True when a poll with this repository would carry a real token.
    ///
    /// Distinct from "an account matched": a matched account whose Keychain
    /// entry has gone reports nothing, and sending no token produces a 401 that
    /// reads like bad credentials rather than a missing account.
    func hasUsableToken(for repo: MonitoredRepo, prompt: Bool = true) -> Bool {
        guard let token = token(for: repo, prompt: prompt) else { return false }
        return !token.isEmpty
    }


    func resolvedAccount(for repo: MonitoredRepo) -> PRAccount? {
        guard repo.visibility.needsCredentials else { return nil }
        let usable = accounts.filter { $0.matches(repo) }
        if let identity = repo.accountIdentity,
           let chosen = usable.first(where: { $0.identity == identity }) {
            return chosen
        }
        return usable.first
    }

    /// The account a repo should use, and whether it actually has a usable
    /// token. Private repos with no credential are reported rather than
    /// silently failing every poll.
    func accountStatus(for repo: MonitoredRepo, prompt: Bool = false) -> (account: PRAccount?, hasToken: Bool) {
        guard repo.visibility.needsCredentials else { return (nil, true) }
        guard let account = resolvedAccount(for: repo) else { return (nil, false) }
        return (account, hasUsableToken(for: repo, prompt: prompt))
    }

    // MARK: - Repositories

    func addRepo(_ repo: MonitoredRepo) {
        repos.removeAll { $0.id == repo.id }
        repos.append(repo)
        persist()
    }

    func updateRepo(_ repo: MonitoredRepo) {
        if let index = repos.firstIndex(where: { $0.id == repo.id }) {
            repos[index] = repo
        } else {
            repos.append(repo)
        }
        persist()
    }

    func removeRepo(_ repo: MonitoredRepo) {
        repos.removeAll { $0.id == repo.id }
        persist()
    }

    func repo(withID id: String) -> MonitoredRepo? {
        repos.first { $0.id == id }
    }

    // MARK: - Ignored PRs

    func isIgnored(_ pr: PullRequest, repo: MonitoredRepo) -> Bool {
        ignoredPRs.contains(pr.fingerprint(remoteKey: repo.id))
    }

    func ignore(_ pr: PullRequest, repo: MonitoredRepo) {
        ignoredPRs.insert(pr.fingerprint(remoteKey: repo.id))
        persist()
    }

    func unignoreAll() {
        ignoredPRs.removeAll()
        persist()
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var accounts: [PRAccount] = []
        var repos: [MonitoredRepo] = []
        var defaultDepth: PRKind.Depth = .changedOnly
        var notifyStyle: PRKind.NotifyStyle = .banner
        var pollingIntervalMinutes: Int = 15
        var monitoringEnabled: Bool = false
        var ignoredPRs: [String] = []
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return }
        isLoading = true
        defer { isLoading = false }
        accounts = snapshot.accounts
        repos = snapshot.repos
        defaultDepth = snapshot.defaultDepth
        notifyStyle = snapshot.notifyStyle
        pollingIntervalMinutes = snapshot.pollingIntervalMinutes
        monitoringEnabled = snapshot.monitoringEnabled
        ignoredPRs = Set(snapshot.ignoredPRs)
        // Deliberately last. This re-keys accounts, and it used to save the file
        // at that moment — before the saved preferences above had been restored —
        // so a launch that migrated an account rewrote the user's monitoring
        // setting back to its "off" default and it silently stopped being
        // remembered.
        // Before the identity migration, because the migration re-keys the
        // Keychain entry from the provider segment of the identity.
        var repaired = repairContradictoryAccounts()
        if migrateAccountIdentities() { repaired = true }
        if repaired { persist() }
    }

    /// Corrects accounts whose stored provider contradicts their own host.
    private func repairContradictoryAccounts() -> Bool {
        var changed = false
        for index in accounts.indices {
            guard let host = accounts[index].normalizedAPIHost,
                  let correct = PRHost.provider(ofHost: host),
                  accounts[index].provider != correct,
                  let baseURL = ForgeDetector.apiBaseURL(provider: correct, host: host)
            else { continue }
            PRLog.write("PR account \"\(accounts[index].username)\" was saved as \(accounts[index].provider) on \(host); using \(correct) instead.")
            accounts[index].provider = correct
            accounts[index].baseURL = baseURL
            changed = true
        }
        return changed
    }

    private func persistUnlessLoading() {
        guard !isLoading else { return }
        persist()
    }

    private func persist() {
        let snapshot = Snapshot(accounts: accounts,
                                repos: repos,
                                defaultDepth: defaultDepth,
                                notifyStyle: notifyStyle,
                                pollingIntervalMinutes: pollingIntervalMinutes,
                                monitoringEnabled: monitoringEnabled,
                                ignoredPRs: Array(ignoredPRs))
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
