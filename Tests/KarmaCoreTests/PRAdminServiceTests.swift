import Foundation
import XCTest
@testable import KarmaCore

/// The Accounts and Watched Repositories dialogs' rules, run against a temporary store and token file. No test
/// reaches the network, starts a job, reads the real caches folder or touches the real Application Support folder.
final class PRAdminServiceTests: XCTestCase {

    /// Records what the service asked of the rest of the feature, and serves a fake cache and review state.
    private final class Recorder {
        var repositoriesChanged: [Set<String>] = []
        var publishes = 0
        var cacheReads = 0
        var removals = 0
        var reviewActive = false
        var pollError: String?
        var cacheBytes: Int64 = 0
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-pradmin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeService(recorder: Recorder = Recorder())
        -> (service: PRAdminService, store: PRStore, recorder: Recorder) {
        let store = PRStore(fileURL: directory.appendingPathComponent("PullRequests.json"))
        store.tokenStorage = FilePRTokenStorage(fileURL: directory.appendingPathComponent("PullRequestTokens.json"))
        let hooks = PRAdminService.Hooks(
            reviewActive: { recorder.reviewActive },
            repositoriesChanged: { recorder.repositoriesChanged.append($0) },
            publish: { recorder.publishes += 1 },
            pollErrorDetail: { recorder.pollError },
            cacheBytes: {
                recorder.cacheReads += 1
                return recorder.cacheBytes
            },
            cachePath: { "/fake/cache" },
            removeCache: {
                recorder.removals += 1
                let freed = recorder.cacheBytes
                recorder.cacheBytes = 0
                return freed
            })
        return (PRAdminService(store: store, hooks: hooks), store, recorder)
    }

    /// Asserts that `body` throws a service error whose text is `expected`.
    private func assertThrowsText<T>(_ expected: String, file: StaticString = #filePath, line: UInt = #line,
                                     _ body: () throws -> T) {
        do {
            _ = try body()
            XCTFail("expected the error \"\(expected)\"", file: file, line: line)
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, expected, file: file, line: line)
        }
    }

    // MARK: - Accounts

    func testAccountFormRefusesMissingUsernameBeforeToken() {
        let (service, _, _) = makeService()

        assertThrowsText("Enter a username to identify this account.") {
            try service.saveAccount(provider: "github", host: "", username: "  ", token: "")
        }
        assertThrowsText("Paste a token to save.") {
            try service.saveAccount(provider: "github", host: "", username: "alice", token: "   ")
        }
        XCTAssertTrue(service.accounts().accounts.isEmpty)
    }

    func testTypedHostNamesItsForgeAndSetsTheIdentity() throws {
        let (service, _, recorder) = makeService()

        let status = try service.saveAccount(provider: "github", host: "https://GitLab.com/",
                                             username: " alice ", token: " secret ")

        XCTAssertEqual(status.text, "Saved alice for GitLab.")
        XCTAssertTrue(status.success)
        let account = try XCTUnwrap(service.accounts().accounts.first)
        XCTAssertEqual(account.identity, "gitlab|gitlab.com|alice")
        XCTAssertEqual(account.provider, "gitlab")
        XCTAssertEqual(account.providerName, "GitLab")
        XCTAssertEqual(account.host, "gitlab.com")
        XCTAssertEqual(account.username, "alice")
        XCTAssertEqual(account.tokenStatus, "stored")
        XCTAssertEqual(recorder.publishes, 1)
        let tokens = FilePRTokenStorage(fileURL: directory.appendingPathComponent("PullRequestTokens.json"))
        XCTAssertEqual(tokens.token(identity: "gitlab|gitlab.com|alice", prompt: false), "secret")
    }

    func testResolveProviderFollowsOnlyAnEditableHost() {
        let (service, _, _) = makeService()

        XCTAssertEqual(service.resolveProvider(provider: "github", host: "gitlab.com"), "gitlab")
        XCTAssertEqual(service.resolveProvider(provider: "github", host: "codeberg.org"), "gitea")
        XCTAssertEqual(service.resolveProvider(provider: "github", host: "example.org"), "github")
        XCTAssertEqual(service.resolveProvider(provider: "github", host: ""), "github")
        // Bitbucket's host is fixed, so the typed text does not move the popup.
        XCTAssertEqual(service.resolveProvider(provider: "bitbucket", host: "gitlab.com"), "bitbucket")
    }

    func testSelfHostedGiteaAccountUsesTheTypedHostOrCodeberg() throws {
        let (service, _, _) = makeService()

        _ = try service.saveAccount(provider: "gitea", host: "Codeberg.org", username: "bob", token: "t")
        _ = try service.saveAccount(provider: "gitea", host: "", username: "carol", token: "t")

        let accounts = service.accounts().accounts
        XCTAssertEqual(accounts.map(\.identity), ["gitea|codeberg.org|bob", "gitea|codeberg.org|carol"])
        XCTAssertEqual(accounts.map(\.providerName), ["Gitea / Forgejo", "Gitea / Forgejo"])
    }

    func testProvidersCarryTheFormHintsOfTheDialog() {
        let (service, _, _) = makeService()

        let providers = service.accounts().providers
        XCTAssertEqual(providers.map(\.id), ["github", "gitlab", "gitea", "bitbucket"])
        XCTAssertEqual(providers.map(\.name), ["GitHub", "GitLab", "Gitea / Forgejo / Codeberg", "Bitbucket"])
        let bitbucket = providers[3]
        XCTAssertFalse(bitbucket.hostEnabled)
        XCTAssertEqual(bitbucket.tokenPlaceholder, "app password (read-only)")
        XCTAssertEqual(bitbucket.hostPlaceholder, "bitbucket.org (Cloud only)")
        XCTAssertEqual(providers[2].tokenPlaceholder, "token (read-only)")
        XCTAssertEqual(providers[2].defaultHost, "codeberg.org")
        XCTAssertEqual(providers[0].defaultHost, "github.com")
    }

    func testAccountSaveListAndRemoveRoundTrip() throws {
        let (service, store, recorder) = makeService()
        _ = try service.saveAccount(provider: "github", host: "", username: "alice", token: "t1")

        let saved = try XCTUnwrap(service.accounts().accounts.first)
        XCTAssertEqual(saved.identity, "github|github.com|alice")
        XCTAssertEqual(saved.host, "github.com")
        XCTAssertEqual(saved.providerName, "GitHub")
        XCTAssertEqual(saved.tokenStatus, "stored")

        // A token removed behind the dialog's back shows as missing, not stored.
        try store.tokenStorage.deleteToken(identity: saved.identity)
        XCTAssertEqual(service.accounts().accounts.first?.tokenStatus, "missing")

        let prompt = try service.removeAccountPrompt(identity: saved.identity)
        XCTAssertEqual(prompt.title, "Remove alice?")
        XCTAssertEqual(prompt.message, "The stored token will be deleted from your Keychain.")
        XCTAssertEqual(prompt.confirmTitle, "Remove")
        XCTAssertEqual(prompt.cancelTitle, "Cancel")

        let before = recorder.publishes
        let removed = try service.removeAccount(identity: saved.identity)
        XCTAssertEqual(removed.text, "Removed alice.")
        XCTAssertTrue(service.accounts().accounts.isEmpty)
        XCTAssertEqual(recorder.publishes, before + 1)
        assertThrowsText("That account is no longer saved.") {
            try service.removeAccountPrompt(identity: saved.identity)
        }
    }

    func testTestingAnAccountRefusesBeforeAnyNetworkCall() throws {
        let (service, store, _) = makeService()
        assertThrowsText("That account is no longer saved.") {
            try service.testAccount(identity: "github|github.com|nobody")
        }

        _ = try service.saveAccount(provider: "github", host: "", username: "alice", token: "t")
        try store.tokenStorage.deleteToken(identity: "github|github.com|alice")
        assertThrowsText("alice: no token in the Keychain \u{2014} re-enter and save it.") {
            try service.testAccount(identity: "github|github.com|alice")
        }
    }

    // MARK: - Repositories

    func testAddingAPublicRepositoryUsesTheDialogDefaults() throws {
        let (service, _, recorder) = makeService()

        let repo = try service.addRepository(url: "https://github.com/owner/name", isPrivate: false,
                                             localPath: "   ", depth: nil, baseBranches: " main, , release ",
                                             accountIdentity: nil)

        XCTAssertEqual(repo.id, "github|https://api.github.com|owner/name")
        XCTAssertEqual(repo.repoSlug, "owner/name")
        XCTAssertEqual(repo.webURL, "https://github.com/owner/name")
        XCTAssertEqual(repo.visibility, "publicRepo")
        XCTAssertEqual(repo.typeText, "Public")
        XCTAssertEqual(repo.depth, "changedOnly")
        XCTAssertEqual(repo.depthTitle, "Changed files only")
        XCTAssertEqual(repo.baseBranches, ["main", "release"])
        XCTAssertNil(repo.localPath)
        XCTAssertTrue(repo.enabled)
        XCTAssertNil(repo.accountIdentity)
        XCTAssertEqual(repo.accountText, "\u{2014}")
        XCTAssertEqual(repo.sourceText, "Remote")
        XCTAssertEqual(repo.watchingTooltip, "Watching this repository")
        XCTAssertEqual(recorder.repositoriesChanged, [[repo.id]])
        XCTAssertEqual(recorder.publishes, 1)

        let listing = service.repositories()
        XCTAssertEqual(listing.repos.map(\.id), [repo.id])
        XCTAssertEqual(listing.depthChoices.first { $0.selected }?.value, "changedOnly")
        XCTAssertNil(listing.pollErrorDetail)
        XCTAssertEqual(listing.cache.label, "No review checkouts on disk")
        XCTAssertEqual(listing.cache.path, "/fake/cache")
    }

    func testAddingAPrivateRepositoryNeedsAUsableAccount() throws {
        let (service, _, recorder) = makeService()

        assertThrowsText("No usable account for this repository\n\n"
                         + "No saved account on https://github.com can reach this private GitHub repository. "
                         + "Add a read-only token in Accounts\u{2026} first.") {
            try service.addRepository(url: "https://github.com/owner/secret", isPrivate: true, localPath: nil,
                                      depth: nil, baseBranches: "", accountIdentity: nil)
        }
        XCTAssertTrue(service.repositories().repos.isEmpty)
        XCTAssertTrue(recorder.repositoriesChanged.isEmpty)

        _ = try service.saveAccount(provider: "github", host: "", username: "alice", token: "t")
        let repo = try service.addRepository(url: "https://github.com/owner/secret", isPrivate: true, localPath: nil,
                                             depth: "fullProject", baseBranches: "", accountIdentity: nil)

        XCTAssertEqual(repo.typeText, "Private")
        XCTAssertEqual(repo.depth, "fullProject")
        XCTAssertEqual(repo.accountIdentity, "github|github.com|alice")
        XCTAssertEqual(repo.accountText, "alice")
        XCTAssertEqual(repo.accountChoices.map(\.title), ["alice (github.com)"])
    }

    func testAddRepositoryRejectsUnreadableURLAndUnknownDepth() {
        let (service, _, _) = makeService()

        assertThrowsText("Enter a full repository URL, for example https://github.com/owner/name.") {
            try service.addRepository(url: "not a url", isPrivate: false, localPath: nil, depth: nil,
                                      baseBranches: "", accountIdentity: nil)
        }
        assertThrowsText("Choose a scan depth from the list.") {
            try service.addRepository(url: "https://github.com/owner/name", isPrivate: false, localPath: nil,
                                      depth: "everything", baseBranches: "", accountIdentity: nil)
        }
    }

    func testPausingAndUpdatingARepositoryKeepsItsIdentity() throws {
        let (service, _, recorder) = makeService()
        let repo = try service.addRepository(url: "https://gitlab.com/group/project", isPrivate: false,
                                             localPath: nil, depth: nil, baseBranches: "", accountIdentity: nil)

        let paused = try service.updateRepository(id: repo.id, change: .init(enabled: false))
        XCTAssertEqual(paused.id, repo.id)
        XCTAssertFalse(paused.enabled)
        XCTAssertEqual(paused.watchingTooltip, "Not being watched \u{2014} click to resume")
        XCTAssertEqual(recorder.repositoriesChanged.last, [])

        let relocated = try service.updateRepository(id: repo.id,
                                                     change: .init(depth: "fullProject", localPath: "  /src/project  "))
        XCTAssertEqual(relocated.localPath, "/src/project")
        XCTAssertEqual(relocated.depth, "fullProject")
        XCTAssertEqual(relocated.sourceText, "Local clone")

        // Making a public repository private needs an account; refusal leaves the repository public.
        assertThrowsText("No usable account for this repository\n\n"
                         + "No saved account on https://gitlab.com can reach this private GitLab repository. "
                         + "Add a read-only token in Accounts\u{2026} first.") {
            try service.updateRepository(id: repo.id, change: .init(isPrivate: true))
        }
        XCTAssertEqual(service.repositories().repos.first?.visibility, "publicRepo")

        let prompt = try service.removeRepositoryPrompt(id: repo.id)
        XCTAssertEqual(prompt.title, "Stop watching group/project?")
        XCTAssertEqual(prompt.message, "Any temporary checkout created for its pull requests stays on disk.")

        try service.removeRepository(id: repo.id)
        XCTAssertTrue(service.repositories().repos.isEmpty)
        assertThrowsText("That repository is no longer watched.") {
            try service.removeRepositoryPrompt(id: repo.id)
        }
    }

    func testDetectionReadsTheURLAndPicksTheAccountLikeTheForm() throws {
        let (service, _, _) = makeService()

        let unreadable = service.detectRepository(url: "not a url", isPrivate: false, accountIdentity: nil)
        XCTAssertFalse(unreadable.recognised)
        XCTAssertEqual(unreadable.statusText, "Could not read that as a repository URL.")
        XCTAssertEqual(unreadable.statusTone, "error")

        let github = service.detectRepository(url: "https://github.com/owner/name", isPrivate: false,
                                              accountIdentity: nil)
        XCTAssertFalse(github.isPrivate)
        XCTAssertEqual(github.statusText, "Public repository: no credentials are used or sent.")
        XCTAssertTrue(github.accounts.isEmpty)

        // Self-hosted forges are ticked private automatically, and with no account the status says so.
        let codeberg = service.detectRepository(url: "https://codeberg.org/owner/repo", isPrivate: false,
                                                accountIdentity: nil)
        XCTAssertTrue(codeberg.isPrivate)
        XCTAssertEqual(codeberg.provider, "gitea")
        XCTAssertEqual(codeberg.statusText,
                       "Private repository: no saved account can reach the forge. Add one in Accounts\u{2026} first.")
        XCTAssertEqual(codeberg.statusTone, "warning")
        XCTAssertNil(codeberg.selectedAccountIdentity)

        _ = try service.saveAccount(provider: "gitea", host: "codeberg.org", username: "bob", token: "t")
        let chosen = service.detectRepository(url: "https://codeberg.org/owner/repo", isPrivate: true,
                                              accountIdentity: nil)
        XCTAssertEqual(chosen.accounts.map(\.title), ["bob (codeberg.org)"])
        XCTAssertEqual(chosen.selectedAccountIdentity, "gitea|codeberg.org|bob")
        XCTAssertEqual(chosen.statusText, "Private repository: uses account \"bob\" on codeberg.org.")
        XCTAssertEqual(chosen.statusTone, "info")
    }

    func testRepositoryTestRefusesBeforeAnyNetworkCall() {
        let (service, _, _) = makeService()

        assertThrowsText("Enter a full repository URL, for example https://github.com/owner/name.") {
            try service.testRepository(url: "not a url", isPrivate: false, accountIdentity: nil)
        }
        assertThrowsText("No saved account can reach https://github.com/owner/name. Add one in Accounts\u{2026} first.") {
            try service.testRepository(url: "https://github.com/owner/name", isPrivate: true, accountIdentity: nil)
        }
    }

    func testPollFailureDetailIsTrimmedAndCacheLabelStatesTheSize() {
        let (service, _, recorder) = makeService()
        recorder.pollError = "  owner/name: the token was rejected  \n"
        recorder.cacheBytes = 2048

        let listing = service.repositories()

        XCTAssertEqual(listing.pollErrorDetail, "owner/name: the token was rejected")
        XCTAssertEqual(listing.cache.bytes, 2048)
        XCTAssertEqual(listing.cache.label, "Review checkouts on disk: 2.0 KB")
        XCTAssertEqual(listing.cache.path, "/fake/cache")
    }

    // MARK: - Review cache

    func testClearCacheRefusesWhileAReviewIsOpen() throws {
        let (service, _, recorder) = makeService()
        recorder.cacheBytes = 4096
        recorder.reviewActive = true

        let refusal = "Close the open review first\n\nThe pull request you are reviewing is being read from this folder. "
            + "Close that review, then clear the cache."
        assertThrowsText(refusal) { try service.clearCachePrompt() }
        assertThrowsText(refusal) { try service.clearCache() }
        XCTAssertEqual(recorder.cacheReads, 0, "the refusal must come before the cache is measured")
        XCTAssertEqual(recorder.removals, 0)

        recorder.reviewActive = false
        let prompt = try XCTUnwrap(try service.clearCachePrompt())
        XCTAssertEqual(prompt.title, "Free 4.0 KB of review checkouts?")
        XCTAssertEqual(prompt.confirmTitle, "Clear Cache")

        let cleared = try service.clearCache()
        XCTAssertEqual(cleared.text, "Cleared 4.0 KB of review checkouts.")
        XCTAssertEqual(recorder.removals, 1)

        XCTAssertNil(try service.clearCachePrompt())
        XCTAssertEqual(try service.clearCache().text, "The review cache is already empty.")
    }
}
