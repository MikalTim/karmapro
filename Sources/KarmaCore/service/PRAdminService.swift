// by cipher.org.uk
import Foundation

/// The two dialogs behind the pull request menu: "Pull Request Accounts" (the forge credentials that private
/// repositories use) and "Watched Repositories" (the repositories polled for new pull requests, and the review
/// checkouts kept on disk).
///
/// The rules those dialogs apply live here, so the web front end and the AppKit windows agree on validation,
/// on which account a private repository uses, and on the wording of every alert and status line. Tokens are
/// read through `PRTokenStorage` and never returned in a DTO, and listing accounts never asks for a token.
///
/// Notifications go out after the store lock is released, so a listener that calls back into this service
/// cannot deadlock.
public final class PRAdminService: @unchecked Sendable {
    public static let shared = PRAdminService()

    /// What the dialogs need from the rest of the feature. The live values reach `PRService`, `PRMonitor` and the
    /// file system; tests replace them so nothing touches the network, the real caches folder or the real review
    /// state.
    struct Hooks {
        var reviewActive: () -> Bool
        var repositoriesChanged: (Set<String>) -> Void
        var publish: () -> Void
        var pollErrorDetail: () -> String?
        var cacheBytes: () -> Int64
        var cachePath: () -> String
        var removeCache: () throws -> Int64

        static let live = Hooks(
            reviewActive: { PRService.shared.hasActiveReview },
            repositoriesChanged: { PRService.shared.repositoriesDidChange(mutedRepoIDs: $0) },
            publish: { PRService.shared.publish() },
            pollErrorDetail: { PRService.shared.state().pollErrorDetail },
            cacheBytes: { PRMonitor.cacheSize() },
            cachePath: { PRMonitor.cacheRoot.path },
            removeCache: { try PRMonitor.clearCache() })
    }

    // MARK: - Data transfer objects

    /// One provider in the account form, with the hints the form sets when the provider changes.
    public struct ProviderDTO: Codable, Sendable {
        public var id: String
        public var name: String
        /// Placeholder of the token field.
        public var tokenPlaceholder: String
        /// Placeholder of the host field.
        public var hostPlaceholder: String
        /// False when the host cannot be typed (Bitbucket is Cloud only).
        public var hostEnabled: Bool
        /// The host used when the host field is left empty.
        public var defaultHost: String

        public init(id: String, name: String, tokenPlaceholder: String, hostPlaceholder: String,
                    hostEnabled: Bool, defaultHost: String) {
            self.id = id
            self.name = name
            self.tokenPlaceholder = tokenPlaceholder
            self.hostPlaceholder = hostPlaceholder
            self.hostEnabled = hostEnabled
            self.defaultHost = defaultHost
        }
    }

    /// One saved account, as the Accounts table shows it.
    public struct AccountDTO: Codable, Sendable {
        /// Keychain key, `provider|host|username`.
        public var identity: String
        /// Provider id, for example "github".
        public var provider: String
        /// Provider name as the table shows it, for example "GitLab".
        public var providerName: String
        /// The forge host; "—" when the account has none.
        public var host: String
        public var username: String
        /// "stored", "missing" or "not checked". "not checked" is only reported where the token store is the
        /// Keychain and nothing has been read from it yet, so listing never prompts.
        public var tokenStatus: String

        public init(identity: String, provider: String, providerName: String, host: String,
                    username: String, tokenStatus: String) {
            self.identity = identity
            self.provider = provider
            self.providerName = providerName
            self.host = host
            self.username = username
            self.tokenStatus = tokenStatus
        }
    }

    /// The Accounts dialog's data: the saved accounts and the provider list with its form hints.
    public struct AccountsDTO: Codable, Sendable {
        public var accounts: [AccountDTO]
        public var providers: [ProviderDTO]

        public init(accounts: [AccountDTO], providers: [ProviderDTO]) {
            self.accounts = accounts
            self.providers = providers
        }
    }

    /// An account that can serve a repository, as a choice in the account picker ("alice (github.com)").
    public struct AccountChoiceDTO: Codable, Sendable {
        public var identity: String
        public var title: String

        public init(identity: String, title: String) {
            self.identity = identity
            self.title = title
        }
    }

    /// A one-line result the dialog shows in its status line. `success` false means the status is an error.
    public struct StatusDTO: Codable, Sendable {
        public var text: String
        public var success: Bool

        public init(text: String, success: Bool) {
            self.text = text
            self.success = success
        }
    }

    /// The question asked before a destructive action, with the buttons' titles.
    public struct ConfirmDTO: Codable, Sendable {
        public var title: String
        public var message: String
        public var confirmTitle: String
        public var cancelTitle: String

        public init(title: String, message: String, confirmTitle: String, cancelTitle: String) {
            self.title = title
            self.message = message
            self.confirmTitle = confirmTitle
            self.cancelTitle = cancelTitle
        }
    }

    /// One watched repository, with every value its row and the edit form show.
    public struct RepoDTO: Codable, Sendable {
        /// `provider|apiBaseURL|slug`, the key every other call uses.
        public var id: String
        public var provider: String
        /// The web address of the repository; shown as the row tooltip.
        public var webURL: String
        public var repoSlug: String
        /// The local clone used instead of a download, or nil.
        public var localPath: String?
        /// Raw visibility, "publicRepo" or "privateRepo".
        public var visibility: String
        /// "Public" or "Private", as the Type column shows it.
        public var typeText: String
        /// Raw scan depth, "changedOnly" or "fullProject".
        public var depth: String
        public var depthTitle: String
        /// Base branches to alert for; empty means every branch.
        public var baseBranches: [String]
        /// The Watching checkbox.
        public var enabled: Bool
        /// The tooltip of the Watching checkbox.
        public var watchingTooltip: String
        /// The account chosen for this repository, or nil.
        public var accountIdentity: String?
        /// The Account column: "—" for public repositories, otherwise the account's username or "none".
        public var accountText: String
        /// The saved accounts that can serve this repository (empty when public).
        public var accountChoices: [AccountChoiceDTO]
        /// The Source column: "Remote" or "Local clone".
        public var sourceText: String

        public init(id: String, provider: String, webURL: String, repoSlug: String, localPath: String?,
                    visibility: String, typeText: String, depth: String, depthTitle: String,
                    baseBranches: [String], enabled: Bool, watchingTooltip: String, accountIdentity: String?,
                    accountText: String, accountChoices: [AccountChoiceDTO], sourceText: String) {
            self.id = id
            self.provider = provider
            self.webURL = webURL
            self.repoSlug = repoSlug
            self.localPath = localPath
            self.visibility = visibility
            self.typeText = typeText
            self.depth = depth
            self.depthTitle = depthTitle
            self.baseBranches = baseBranches
            self.enabled = enabled
            self.watchingTooltip = watchingTooltip
            self.accountIdentity = accountIdentity
            self.accountText = accountText
            self.accountChoices = accountChoices
            self.sourceText = sourceText
        }
    }

    /// Changes to one repository. A nil field is left as it is.
    public struct RepoUpdateDTO: Codable, Sendable {
        /// Switches the repository between public and private.
        public var isPrivate: Bool?
        public var accountIdentity: String?
        /// Raw scan depth.
        public var depth: String?
        /// Comma-separated base branches, as the form field takes them.
        public var baseBranches: String?
        /// Local clone path; empty clears it.
        public var localPath: String?
        public var enabled: Bool?

        public init(isPrivate: Bool? = nil, accountIdentity: String? = nil, depth: String? = nil,
                    baseBranches: String? = nil, localPath: String? = nil, enabled: Bool? = nil) {
            self.isPrivate = isPrivate
            self.accountIdentity = accountIdentity
            self.depth = depth
            self.baseBranches = baseBranches
            self.localPath = localPath
            self.enabled = enabled
        }
    }

    /// The size of the review checkouts on disk.
    public struct CacheDTO: Codable, Sendable {
        public var bytes: Int64
        /// "No review checkouts on disk" or "Review checkouts on disk: 1.4 GB".
        public var label: String
        /// The cache folder; shown as the label's tooltip.
        public var path: String

        public init(bytes: Int64, label: String, path: String) {
            self.bytes = bytes
            self.label = label
            self.path = path
        }
    }

    /// The Watched Repositories dialog's data.
    public struct RepositoriesDTO: Codable, Sendable {
        public var repos: [RepoDTO]
        /// The Scan depth choices of the add form; the selected one is the default depth.
        public var depthChoices: [PRChoiceDTO]
        /// Full text of the last poll failure, or nil when the last poll worked.
        public var pollErrorDetail: String?
        public var cache: CacheDTO

        public init(repos: [RepoDTO], depthChoices: [PRChoiceDTO], pollErrorDetail: String?, cache: CacheDTO) {
            self.repos = repos
            self.depthChoices = depthChoices
            self.pollErrorDetail = pollErrorDetail
            self.cache = cache
        }
    }

    /// What the add form shows while a URL is being typed: the detected forge, the private box, the account
    /// picker and the status line. Mirrors `updateDetection` and `updatePrivacyHint`.
    public struct DetectionDTO: Codable, Sendable {
        /// False when the text is not a repository URL; then `accounts` is empty and `statusText` says so.
        public var recognised: Bool
        /// Whether the private box is ticked after detection (ticked for self-hosted forges).
        public var isPrivate: Bool
        public var provider: String?
        public var webURL: String?
        public var repoSlug: String?
        /// The accounts that can serve the repository; empty unless it is private.
        public var accounts: [AccountChoiceDTO]
        /// The account the picker selects, or nil for public repositories and when no account can serve it.
        public var selectedAccountIdentity: String?
        /// The status line's text, or nil while the URL is empty.
        public var statusText: String?
        /// "error", "warning" or "info" for the status line; nil with no text.
        public var statusTone: String?

        public init(recognised: Bool, isPrivate: Bool, provider: String?, webURL: String?, repoSlug: String?,
                    accounts: [AccountChoiceDTO], selectedAccountIdentity: String?, statusText: String?,
                    statusTone: String?) {
            self.recognised = recognised
            self.isPrivate = isPrivate
            self.provider = provider
            self.webURL = webURL
            self.repoSlug = repoSlug
            self.accounts = accounts
            self.selectedAccountIdentity = selectedAccountIdentity
            self.statusText = statusText
            self.statusTone = statusTone
        }
    }

    // MARK: - Provider rules

    /// The providers in the order the form lists them.
    private static let providerNames: [(id: String, name: String)] = [
        ("github", "GitHub"),
        ("gitlab", "GitLab"),
        ("gitea", "Gitea / Forgejo / Codeberg"),
        ("bitbucket", "Bitbucket"),
    ]

    /// The hints `providerChanged` sets for a provider.
    static func providerHints(_ provider: String) -> (tokenPlaceholder: String, hostPlaceholder: String, hostEnabled: Bool) {
        switch provider {
        case "bitbucket":
            // Bitbucket calls its read-only credential an app password and is Cloud-only, so its host is fixed.
            return ("app password (read-only)", "bitbucket.org (Cloud only)", false)
        case "gitea":
            // Gitea has no single public host, so it is the one provider whose host must be typed.
            return ("token (read-only)", "host, e.g. codeberg.org", true)
        default:
            return ("read-only token", "host, e.g. gitlab.com", true)
        }
    }

    /// The name the repository alerts use for a provider. Gitea-family forges have no single name here.
    static func forgeName(_ provider: String) -> String {
        switch provider {
        case "github": return "GitHub"
        case "gitlab": return "GitLab"
        case "bitbucket": return "Bitbucket"
        case "gitea": return "the forge"
        default: return "that provider"
        }
    }

    // MARK: - State

    private let store: PRStore
    private let hooks: Hooks
    /// Guards `store`, which is not thread-safe. Held only while touching the store, never across a notification.
    private let lock = NSLock()

    init(store: PRStore = .shared, hooks: Hooks = .live) {
        self.store = store
        self.hooks = hooks
    }

    /// Runs `body` with the lock held. Callers send notifications after this returns.
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - Accounts

    /// The Accounts dialog's table and the provider list.
    public func accounts() -> AccountsDTO {
        let rows = locked { store.accounts.map(accountDTO) }
        let providers = Self.providerNames.map { provider in
            let hints = Self.providerHints(provider.id)
            return ProviderDTO(id: provider.id, name: provider.name, tokenPlaceholder: hints.tokenPlaceholder,
                               hostPlaceholder: hints.hostPlaceholder, hostEnabled: hints.hostEnabled,
                               defaultHost: ForgeDetector.defaultHost(for: provider.id))
        }
        return AccountsDTO(accounts: rows, providers: providers)
    }

    /// The provider the form should show for a typed host. A known public host names its own forge, so the
    /// provider list moves to it, as `controlTextDidChange` does. Only applies while the host field is editable.
    public func resolveProvider(provider: String, host: String) -> String {
        let typed = PRHost.bare(host)
        guard Self.providerHints(provider).hostEnabled, !typed.isEmpty else { return provider }
        return ForgeDetector.provider(forHost: typed) ?? provider
    }

    /// Saves (or replaces) an account and its token, with the validation and status text of the Accounts dialog.
    ///
    /// The typed host is authoritative over the provider list, and a bare host is taken from a pasted URL. The
    /// username and token are trimmed before use.
    public func saveAccount(provider: String, host: String, username: String, token: String) throws -> StatusDTO {
        guard Self.providerNames.contains(where: { $0.id == provider }) else {
            throw KarmaServiceError.invalid("Choose a provider from the list.")
        }
        let typedHost = PRHost.bare(host)
        let hostEnabled = Self.providerHints(provider).hostEnabled
        let resolvedProvider = resolveProvider(provider: provider, host: host)
        let chosenHost = hostEnabled && !typedHost.isEmpty ? typedHost : ForgeDetector.defaultHost(for: provider)

        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw KarmaServiceError.invalid("Enter a username to identify this account.")
        }
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            throw KarmaServiceError.invalid("Paste a token to save.")
        }
        // A host with no API root is a provider this build cannot reach, and saving it would leave an account
        // that silently matches nothing.
        guard let baseURL = ForgeDetector.apiBaseURL(provider: resolvedProvider, host: chosenHost) else {
            throw KarmaServiceError.invalid("That provider does not support that host.")
        }
        let account = PRAccount(identity: "\(resolvedProvider)|\(chosenHost)|\(name)", provider: resolvedProvider,
                                username: name, baseURL: baseURL)

        try locked { try store.saveAccount(account, token: secret) }
        hooks.publish()
        return StatusDTO(text: "Saved \(account.username) for \(account.providerName).", success: true)
    }

    /// Checks a saved account's token against its forge. Returns the id of a job whose result is a `StatusDTO`.
    ///
    /// The Keychain is read here, as "Test Connection" reads it, so this may prompt on macOS.
    public func testAccount(identity: String) throws -> String {
        let (account, token) = try locked { () throws -> (PRAccount, String) in
            let account = try savedAccount(identity)
            guard let token = store.tokenStorage.token(identity: account.identity, prompt: true) else {
                throw KarmaServiceError.invalid("\(account.username): no token in the Keychain \u{2014} re-enter and save it.")
            }
            return (account, token)
        }
        return KarmaJobCenter.shared.start(kind: "pr-account-test") { context in
            context.progress(done: 0, total: 0, stage: "Testing \(account.username)\u{2026}")
            let status: StatusDTO
            switch ForgeRegistry.verifyToken(provider: account.provider, baseURL: account.baseURL,
                                             token: token, username: account.username) {
            case .success(let name):
                status = StatusDTO(text: "\(account.username): connected as \(name).", success: true)
            case .failure(let error):
                status = StatusDTO(text: "\(account.username): \(error.message)", success: false)
            }
            return KarmaJSON.data(status)
        }
    }

    /// The question asked before an account is removed.
    public func removeAccountPrompt(identity: String) throws -> ConfirmDTO {
        let account = try locked { try savedAccount(identity) }
        return ConfirmDTO(title: "Remove \(account.username)?",
                          message: "The stored token will be deleted from your Keychain.",
                          confirmTitle: "Remove", cancelTitle: "Cancel")
    }

    /// Removes an account and its token.
    public func removeAccount(identity: String) throws -> StatusDTO {
        let account = try locked { () throws -> PRAccount in
            let account = try savedAccount(identity)
            try store.removeAccount(account)
            return account
        }
        hooks.publish()
        return StatusDTO(text: "Removed \(account.username).", success: true)
    }

    /// Must be called with the lock held.
    private func savedAccount(_ identity: String) throws -> PRAccount {
        guard let account = store.accounts.first(where: { $0.identity == identity }) else {
            throw KarmaServiceError.notFound("That account is no longer saved.")
        }
        return account
    }

    /// Must be called with the lock held. Never reads the token.
    private func accountDTO(_ account: PRAccount) -> AccountDTO {
        AccountDTO(identity: account.identity, provider: account.provider, providerName: account.providerName,
                   host: account.normalizedAPIHost ?? "\u{2014}", username: account.username,
                   tokenStatus: tokenStatus(for: account))
    }

    /// What the Token column shows. With the Keychain it reports only what is already cached, so opening the
    /// dialog never raises an unlock prompt; "Test" or saving resolves it. Other stores are read directly, which
    /// does not prompt.
    private func tokenStatus(for account: PRAccount) -> String {
        #if canImport(Security) && canImport(LocalAuthentication)
        if store.tokenStorage is KeychainPRTokenStorage {
            let state = PRCredentialStore.cachedState(identity: account.identity)
            guard state.isCached else { return "not checked" }
            return state.token == nil ? "missing" : "stored"
        }
        #endif
        return store.tokenStorage.token(identity: account.identity, prompt: false) == nil ? "missing" : "stored"
    }

    // MARK: - Repositories

    /// The Watched Repositories dialog's table, its scan depth choices, the poll failure and the cache size.
    public func repositories() -> RepositoriesDTO {
        let (repos, depths) = locked { () -> ([RepoDTO], [PRChoiceDTO]) in
            (store.repos.map(repoDTO), depthChoices())
        }
        let bytes = hooks.cacheBytes()
        let cache = CacheDTO(bytes: bytes,
                             label: bytes == 0 ? "No review checkouts on disk"
                                               : "Review checkouts on disk: \(PRMonitor.formattedSize(bytes))",
                             path: hooks.cachePath())
        let detail = hooks.pollErrorDetail()?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RepositoriesDTO(repos: repos, depthChoices: depths,
                               pollErrorDetail: detail?.isEmpty == false ? detail : nil, cache: cache)
    }

    /// Reads a pasted repository URL the way the add form does while it is typed.
    ///
    /// The private box is ticked for self-hosted forges. The account picker lists the accounts that can serve the
    /// repository when it is private, and the status line describes the state. Never prompts for a token.
    public func detectRepository(url: String, isPrivate: Bool, accountIdentity: String?) -> DetectionDTO {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return DetectionDTO(recognised: false, isPrivate: isPrivate, provider: nil, webURL: nil, repoSlug: nil,
                                accounts: [], selectedAccountIdentity: nil, statusText: nil, statusTone: nil)
        }
        guard let endpoint = ForgeDetector.detect(from: text) else {
            return DetectionDTO(recognised: false, isPrivate: isPrivate, provider: nil, webURL: nil, repoSlug: nil,
                                accounts: [], selectedAccountIdentity: nil,
                                statusText: "Could not read that as a repository URL.", statusTone: "error")
        }
        let privateNow = isPrivate || endpoint.provider == "gitea" || endpoint.visibility == .privateRepo
        guard privateNow else {
            return DetectionDTO(recognised: true, isPrivate: false, provider: endpoint.provider,
                                webURL: endpoint.webURL, repoSlug: endpoint.repoSlug, accounts: [],
                                selectedAccountIdentity: nil,
                                statusText: "Public repository: no credentials are used or sent.", statusTone: "info")
        }
        let probe = MonitoredRepo(provider: endpoint.provider, baseURL: endpoint.apiBaseURL,
                                  webURL: endpoint.webURL, repoSlug: endpoint.repoSlug, visibility: .privateRepo)
        let usable = locked { store.accounts(for: probe) }
        let selected = Self.selectedAccount(usable, requested: accountIdentity)
        let statusText: String
        let tone: String
        if let chosen = usable.first(where: { $0.identity == selected }) {
            statusText = "Private repository: uses account \"\(chosen.username)\" on \(chosen.normalizedAPIHost ?? chosen.baseURL)."
            tone = "info"
        } else {
            statusText = "Private repository: no saved account can reach \(Self.forgeName(endpoint.provider)). Add one in Accounts\u{2026} first."
            tone = "warning"
        }
        return DetectionDTO(recognised: true, isPrivate: true, provider: endpoint.provider,
                            webURL: endpoint.webURL, repoSlug: endpoint.repoSlug,
                            accounts: usable.map(Self.choice), selectedAccountIdentity: selected,
                            statusText: statusText, statusTone: tone)
    }

    /// Starts watching a repository.
    ///
    /// Defaults match the add form: public, the default scan depth, every branch, no local clone and no account.
    /// A private repository needs a usable account, or the add is refused with the dialog's alert text. A new
    /// repository's already-open pull requests are not announced.
    public func addRepository(url: String, isPrivate: Bool, localPath: String?, depth: String?,
                              baseBranches: String, accountIdentity: String?) throws -> RepoDTO {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = ForgeDetector.detect(from: text) else {
            throw KarmaServiceError.invalid("Enter a full repository URL, for example https://github.com/owner/name.")
        }
        let visibility: PRKind.Visibility = isPrivate ? .privateRepo : .publicRepo
        let branches = Self.branchList(baseBranches)
        let path = Self.trimmedOrNil(localPath)

        let repo = try locked { () throws -> MonitoredRepo in
            let scanDepth = try Self.depthValue(depth, fallback: store.defaultDepth)
            var repo = MonitoredRepo(provider: endpoint.provider, baseURL: endpoint.apiBaseURL,
                                     webURL: endpoint.webURL, repoSlug: endpoint.repoSlug, localPath: path,
                                     visibility: visibility, depth: scanDepth, baseBranches: branches,
                                     accountIdentity: nil)
            if isPrivate {
                repo.accountIdentity = Self.selectedAccount(store.accounts(for: repo), requested: accountIdentity)
                guard store.hasUsableToken(for: repo) else {
                    throw KarmaServiceError.invalid(Self.noAccountMessage(endpoint))
                }
            }
            store.addRepo(repo)
            return repo
        }
        hooks.repositoriesChanged([repo.id])
        hooks.publish()
        return locked { repoDTO(repo) }
    }

    /// Changes one watched repository. Switching a repository to private, or choosing its account, needs a usable
    /// account; other changes (for example pausing it) never do, so a repository whose account was deleted can
    /// still be paused.
    public func updateRepository(id: String, change: RepoUpdateDTO) throws -> RepoDTO {
        let repo = try locked { () throws -> MonitoredRepo in
            var repo = try savedRepo(id)
            if let isPrivate = change.isPrivate {
                repo.visibility = isPrivate ? .privateRepo : .publicRepo
                if !repo.visibility.needsCredentials { repo.accountIdentity = nil }
            }
            if let depth = change.depth {
                repo.depth = try Self.depthValue(depth, fallback: repo.depth)
            }
            if let branches = change.baseBranches {
                repo.baseBranches = Self.branchList(branches)
            }
            if let path = change.localPath {
                repo.localPath = Self.trimmedOrNil(path)
            }
            if let enabled = change.enabled {
                repo.enabled = enabled
            }
            if repo.visibility.needsCredentials, change.isPrivate == true || change.accountIdentity != nil {
                repo.accountIdentity = Self.selectedAccount(store.accounts(for: repo),
                                                            requested: change.accountIdentity ?? repo.accountIdentity)
                guard store.hasUsableToken(for: repo) else {
                    throw KarmaServiceError.invalid(Self.noAccountMessage(provider: repo.provider,
                                                                          webURL: repo.webURL,
                                                                          repoSlug: repo.repoSlug))
                }
            }
            store.updateRepo(repo)
            return repo
        }
        hooks.repositoriesChanged([])
        hooks.publish()
        return locked { repoDTO(repo) }
    }

    /// The question asked before a repository is removed.
    public func removeRepositoryPrompt(id: String) throws -> ConfirmDTO {
        let repo = try locked { try savedRepo(id) }
        return ConfirmDTO(title: "Stop watching \(repo.repoSlug)?",
                          message: "Any temporary checkout created for its pull requests stays on disk.",
                          confirmTitle: "Remove", cancelTitle: "Cancel")
    }

    /// Stops watching a repository. Its checkouts stay on disk, as the dialog says.
    public func removeRepository(id: String) throws {
        try locked { store.removeRepo(try savedRepo(id)) }
        hooks.repositoriesChanged([])
        hooks.publish()
    }

    /// Checks that a repository's URL and account reach the forge. Returns the id of a job whose result is a
    /// `StatusDTO`. Refusals (no URL, no account) are thrown at once, as the dialog shows them in its status line.
    public func testRepository(url: String, isPrivate: Bool, accountIdentity: String?) throws -> String {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = ForgeDetector.detect(from: text) else {
            throw KarmaServiceError.invalid("Enter a full repository URL, for example https://github.com/owner/name.")
        }
        let visibility: PRKind.Visibility = isPrivate ? .privateRepo : .publicRepo
        let (candidate, token) = try locked { () throws -> (MonitoredRepo, String?) in
            var candidate = MonitoredRepo(provider: endpoint.provider, baseURL: endpoint.apiBaseURL,
                                          webURL: endpoint.webURL, repoSlug: endpoint.repoSlug,
                                          visibility: visibility)
            if visibility.needsCredentials {
                candidate.accountIdentity = Self.selectedAccount(store.accounts(for: candidate),
                                                                 requested: accountIdentity)
                // Testing with no usable account cannot succeed, and the auth error it produces reads like bad
                // credentials rather than a missing account.
                guard store.accountStatus(for: candidate, prompt: true).hasToken else {
                    throw KarmaServiceError.invalid("No saved account can reach \(endpoint.webURL). Add one in Accounts\u{2026} first.")
                }
            }
            return (candidate, store.token(for: candidate))
        }
        let webURL = endpoint.webURL
        return KarmaJobCenter.shared.start(kind: "pr-repo-test") { context in
            context.progress(done: 0, total: 0, stage: "Testing connection to \(webURL)\u{2026}")
            let result = ForgeRegistry.adapter(for: candidate.provider, token: token).testConnection(for: candidate)
            PRLog.write("connection test \(webURL): \(result)")
            let status: StatusDTO
            switch result {
            case .success:
                status = StatusDTO(text: "Connection to \(webURL) works.", success: true)
            case .failure(let error):
                status = StatusDTO(text: error.message, success: false)
            }
            return KarmaJSON.data(status)
        }
    }

    /// Must be called with the lock held.
    private func savedRepo(_ id: String) throws -> MonitoredRepo {
        guard let repo = store.repo(withID: id) else {
            throw KarmaServiceError.notFound("That repository is no longer watched.")
        }
        return repo
    }

    /// Must be called with the lock held.
    private func repoDTO(_ repo: MonitoredRepo) -> RepoDTO {
        let needsAccount = repo.visibility.needsCredentials
        let accountText: String
        if !needsAccount {
            accountText = "\u{2014}"
        } else if let identity = repo.accountIdentity,
                  let account = store.accounts.first(where: { $0.identity == identity }) {
            accountText = account.username
        } else {
            accountText = store.accountStatus(for: repo).account?.username ?? "none"
        }
        return RepoDTO(id: repo.id, provider: repo.provider, webURL: repo.webURL, repoSlug: repo.repoSlug,
                       localPath: repo.localPath, visibility: repo.visibility.rawValue,
                       typeText: needsAccount ? "Private" : "Public", depth: repo.depth.rawValue,
                       depthTitle: repo.depth.title, baseBranches: repo.baseBranches, enabled: repo.enabled,
                       watchingTooltip: repo.enabled ? "Watching this repository"
                                                     : "Not being watched \u{2014} click to resume",
                       accountIdentity: repo.accountIdentity, accountText: accountText,
                       accountChoices: store.accounts(for: repo).map(Self.choice),
                       sourceText: repo.localPath == nil ? "Remote" : "Local clone")
    }

    /// Must be called with the lock held.
    private func depthChoices() -> [PRChoiceDTO] {
        PRKind.Depth.allCases.map { depth in
            PRChoiceDTO(value: depth.rawValue, title: depth.title, explanation: depth.explanation,
                        selected: depth == store.defaultDepth)
        }
    }

    // MARK: - Review cache

    /// The question asked before the review checkouts are removed, or nil when there is nothing to remove.
    /// Refuses while a review is open, because its files are being read from the cache.
    public func clearCachePrompt() throws -> ConfirmDTO? {
        try refuseWhileReviewOpen()
        let bytes = hooks.cacheBytes()
        guard bytes > 0 else { return nil }
        return ConfirmDTO(title: "Free \(PRMonitor.formattedSize(bytes)) of review checkouts?",
                          message: "Removes every temporary pull request checkout. Watching and credentials are untouched. "
                                 + "A review that is reopened will be downloaded again.",
                          confirmTitle: "Clear Cache", cancelTitle: "Cancel")
    }

    /// Removes every temporary review checkout. Refuses while a review is open.
    public func clearCache() throws -> StatusDTO {
        try refuseWhileReviewOpen()
        guard hooks.cacheBytes() > 0 else {
            return StatusDTO(text: "The review cache is already empty.", success: true)
        }
        do {
            let freed = try hooks.removeCache()
            return StatusDTO(text: "Cleared \(PRMonitor.formattedSize(freed)) of review checkouts.", success: true)
        } catch {
            throw PRMessageError("Could not clear the cache\n\n\(error.localizedDescription)")
        }
    }

    private func refuseWhileReviewOpen() throws {
        guard hooks.reviewActive() else { return }
        throw KarmaServiceError.busy("Close the open review first\n\nThe pull request you are reviewing is being read "
                                   + "from this folder. Close that review, then clear the cache.")
    }

    // MARK: - Pure rules

    /// The account a private repository uses: the requested one when it can reach the repository, otherwise the
    /// first that can. Nil when none can.
    private static func selectedAccount(_ usable: [PRAccount], requested: String?) -> String? {
        if let requested, usable.contains(where: { $0.identity == requested }) { return requested }
        return usable.first?.identity
    }

    private static func choice(_ account: PRAccount) -> AccountChoiceDTO {
        AccountChoiceDTO(identity: account.identity,
                         title: "\(account.username) (\(account.normalizedAPIHost ?? account.baseURL))")
    }

    /// The text the form's scan depth field maps to. Nil uses the default depth.
    private static func depthValue(_ raw: String?, fallback: PRKind.Depth) throws -> PRKind.Depth {
        guard let raw = raw else { return fallback }
        guard let depth = PRKind.Depth(rawValue: raw) else {
            throw KarmaServiceError.invalid("Choose a scan depth from the list.")
        }
        return depth
    }

    /// Comma-separated branch names, trimmed, with empty entries dropped.
    private static func branchList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Trimmed text, or nil when nothing is left.
    private static func trimmedOrNil(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func noAccountMessage(_ endpoint: ForgeDetector.Endpoint) -> String {
        noAccountMessage(provider: endpoint.provider, webURL: endpoint.webURL, repoSlug: endpoint.repoSlug)
    }

    /// The alert shown when a private repository has no usable account. Title and detail are joined by a blank line.
    private static func noAccountMessage(provider: String, webURL: String, repoSlug: String) -> String {
        let host = webURL.replacingOccurrences(of: "/\(repoSlug)", with: "")
        return "No usable account for this repository\n\n"
            + "No saved account on \(host) can reach this private \(forgeName(provider)) repository. "
            + "Add a read-only token in Accounts\u{2026} first."
    }
}
