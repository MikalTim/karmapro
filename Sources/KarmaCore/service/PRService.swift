// by cipher.org.uk
import Foundation

/// One option of a setting that offers a fixed list (scan depth, alert style).
public struct PRChoiceDTO: Codable, Sendable {
    /// The value to send back to select this option.
    public var value: String
    public var title: String
    /// Longer text the menu shows as a tooltip; nil for options that have none.
    public var explanation: String?
    public var selected: Bool
}

/// One open pull request in the watch list.
public struct PRItemDTO: Codable, Sendable {
    public var repoID: String
    public var repoSlug: String
    public var prID: Int
    public var number: Int
    public var title: String
    public var author: String
    public var headBranch: String
    public var baseBranch: String
    public var webURL: String
    /// True when the last poll saw it for the first time.
    public var isNew: Bool
}

/// The strip shown above the file tree while a pull request review is open (`PRBannerView`).
public struct PRReviewBannerDTO: Codable, Sendable {
    /// "PR #12 Fix login". Also the window title during the review.
    public var title: String
    /// "Reviewing PR #12 · owner/name · 3 files".
    public var subtitle: String
    /// The repository's web address, shown as the tooltip.
    public var detail: String
    /// Whether "Show All Files" is offered: only while the tree is still pruned to the changed files.
    public var showAllAvailable: Bool
}

/// Everything the pull request menu and the review banner show.
public struct PRStateDTO: Codable, Sendable {
    public var monitoringEnabled: Bool
    public var pollingIntervalMinutes: Int
    public var depthChoices: [PRChoiceDTO]
    public var notifyChoices: [PRChoiceDTO]
    /// One-line summary of failed polls (for the menu); nil when the last poll worked.
    public var pollError: String?
    /// Every failure with its detail (for the repositories dialog).
    public var pollErrorDetail: String?
    public var items: [PRItemDTO]
    /// How many repositories are watched.
    public var repoCount: Int
    public var gitAvailable: Bool
    /// What to tell the user when `gitAvailable` is false; nil otherwise.
    public var gitUnavailableMessage: String?
    /// The open review, or nil.
    public var review: PRReviewBannerDTO?
}

/// One line of a file's patch with the colour class the changes window gives it.
public struct PRDiffLineDTO: Codable, Sendable {
    public var text: String
    /// "hunk" (`@@`), "added", "removed", "meta" (`index`, `Binary`) or "context".
    public var kind: String
    /// An added line the heuristic wants read closely (yellow background, bold).
    public var suspicious: Bool
}

public struct PRChangedFileDTO: Codable, Sendable {
    /// Path relative to the repository root.
    public var path: String
    /// Absolute path of the file in the review checkout, to open it in the viewer.
    public var absolutePath: String
    /// The text of the file picker: "M  src/a.c" or "A  src/b.c (added)".
    public var title: String
    /// "+3  −1 (was old/path)  •  1 line(s) worth reading closely".
    public var summary: String
    public var lines: [PRDiffLineDTO]
}

/// The changes window (`PRDiffWindowController`).
public struct PRChangesDTO: Codable, Sendable {
    public var windowTitle: String
    public var files: [PRChangedFileDTO]
    /// The picker's only entry when `files` is empty.
    public var emptyTitle: String
    /// The text area's content when `files` is empty.
    public var emptyMessage: String
}

/// The report window (`PRReportWindowController`).
public struct PRReportDTO: Codable, Sendable {
    public var windowTitle: String
    public var markdown: String
    /// The suggested file name, for example `PR-12-fix-login.md`.
    public var suggestedName: String
    public var statusText: String
    /// The message of the save panel.
    public var saveMessage: String
}

/// The question asked before a pull request scan (`promptForAIPullRequestScan`).
public struct PRScanPromptDTO: Codable, Sendable {
    public var title: String
    public var message: String
    /// In button order: "headOnly", "both", "none".
    public var choices: [PRChoiceDTO]
}

/// The "About Pull Request Reviews" text.
public struct PRAboutDTO: Codable, Sendable {
    public var title: String
    public var message: String
}

/// One alert for a new pull request (`pr.notify`).
public struct PRNotificationDTO: Codable, Sendable {
    public var repoID: String
    public var prID: Int
    /// "owner/name #12".
    public var title: String
    public var body: String
}

struct PRNotifyEvent: Codable {
    var items: [PRNotificationDTO]
    var allowSound: Bool
}

struct PRReviewEvent: Codable {
    var state: String
}

/// The pull request feature as the menu bar item and the main window drive it: the poller, its settings, and
/// reviewing a pull request as an ordinary folder (`PRReviewCoordinator`, `PRMenuBarController`,
/// `PRNotifier`, and the pull request parts of `MainWindowController`).
///
/// Everything the poller reports comes back on `KarmaCallbackQueue.queue`, so a front end without a UI thread
/// must set that queue before the first use of `shared`. Accounts and watched repositories are `PRAdminService`.
public final class PRService: @unchecked Sendable {
    public static let shared = PRService()

    /// Most alerts announced for one poll (`PRNotifier.maxAlertsPerPoll`).
    static let maxAlertsPerPoll = 5

    static let aboutMessage = """
        Karma Pro watches the repositories you list and alerts you when a new pull request arrives.

        \u{2022} Public repositories need no credentials.
        \u{2022} Private repositories are opt-in per repository and use a read-only token you supply, stored securely on this machine.
        \u{2022} Reviews are read-only: Karma Pro never approves, comments on, or posts to any pull request.
        \u{2022} Reports are Markdown files you save yourself.

        Pull requests are polled while Karma Pro is running. Nothing is fetched when the app is closed.
        """

    private static let gitIsAvailable: Bool = GitRunner.isAvailable()

    private let monitor = PRMonitor()
    private let workspace: KarmaWorkspace
    private let jobs: KarmaJobCenter
    private let bus: KarmaEventBus
    private let lock = NSLock()
    /// The poller's results as of its last change; the poller itself is only touched on the callback queue.
    private var items: [PRActionItem] = []
    private var pollError: String?
    private var pollErrorDetail: String?
    private var preparingJob: String?

    init(workspace: KarmaWorkspace = .shared, jobs: KarmaJobCenter = .shared, bus: KarmaEventBus = .shared) {
        self.workspace = workspace
        self.jobs = jobs
        self.bus = bus
        monitor.presenter = self
        monitor.onChange = { [weak self] in self?.monitorChanged() }
    }

    // MARK: - Lifecycle

    /// Starts polling if the user had left monitoring on (`PRReviewCoordinator.install`).
    /// Monitoring stays off on a fresh install, so this never causes network traffic by itself.
    public func start() {
        KarmaCallbackQueue.queue.async { [monitor] in monitor.start() }
    }

    /// Stops polling and removes an open review's checkout (`PRReviewCoordinator.uninstall`).
    public func stop() {
        KarmaCallbackQueue.queue.async { [monitor] in monitor.stop() }
        leaveReview(removeCheckout: true)
    }

    // MARK: - State

    public func state() -> PRStateDTO {
        let store = PRStore.shared
        lock.lock()
        let items = self.items
        let pollError = self.pollError
        let pollErrorDetail = self.pollErrorDetail
        lock.unlock()

        let review = workspace.read { state in
            state.reviewSession.map { session in
                PRReviewBannerDTO(title: session.context.title,
                                  subtitle: session.badgeText,
                                  detail: session.context.repo.webURL,
                                  showAllAvailable: !state.showAllFiles)
            }
        }
        let gitAvailable = Self.gitIsAvailable
        return PRStateDTO(
            monitoringEnabled: store.monitoringEnabled,
            pollingIntervalMinutes: store.pollingIntervalMinutes,
            depthChoices: PRKind.Depth.allCases.map {
                PRChoiceDTO(value: $0.rawValue, title: $0.title, explanation: $0.explanation,
                            selected: store.defaultDepth == $0)
            },
            notifyChoices: PRKind.NotifyStyle.allCases.map {
                PRChoiceDTO(value: $0.rawValue, title: $0.title, explanation: nil,
                            selected: store.notifyStyle == $0)
            },
            pollError: pollError,
            pollErrorDetail: pollErrorDetail,
            items: items.map(Self.dto),
            repoCount: store.repos.count,
            gitAvailable: gitAvailable,
            gitUnavailableMessage: gitAvailable ? nil : GitRunner.unavailableMessage,
            review: review)
    }

    public func about() -> PRAboutDTO {
        PRAboutDTO(title: "Pull Request Reviews", message: Self.aboutMessage)
    }

    private static func dto(_ item: PRActionItem) -> PRItemDTO {
        PRItemDTO(repoID: item.repo.id, repoSlug: item.repo.repoSlug, prID: item.pr.id, number: item.pr.number,
                  title: item.pr.title, author: item.pr.author, headBranch: item.pr.headBranch,
                  baseBranch: item.pr.baseBranch, webURL: item.pr.webURL, isNew: item.isNew)
    }

    /// Posts the whole state as `pr.changed`.
    func publish() {
        bus.post("pr.changed", state())
    }

    /// Runs on the callback queue after every poll and after the watch list changes.
    private func monitorChanged() {
        lock.lock()
        items = monitor.items
        pollError = monitor.currentErrorSummary
        pollErrorDetail = monitor.currentError
        lock.unlock()
        publish()
    }

    // MARK: - The menu's actions

    /// "Enable Monitoring…" and "Disable Monitoring" (`PRMenuBarController.enableMonitoring`/`disableMonitoring`).
    public func setMonitoring(_ enabled: Bool) throws {
        let store = PRStore.shared
        if enabled {
            guard !store.repos.isEmpty else {
                throw KarmaServiceError.invalid("No repositories yet: add a repository to watch before enabling monitoring.")
            }
            guard Self.gitIsAvailable else {
                throw KarmaServiceError.invalid(GitRunner.unavailableMessage)
            }
            store.monitoringEnabled = true
            // `start` so the repeating poll runs too; `repositoriesDidChange` then polls at once.
            KarmaCallbackQueue.queue.async { [monitor] in monitor.start() }
            repositoriesDidChange()
        } else {
            store.monitoringEnabled = false
            KarmaCallbackQueue.queue.async { [monitor] in monitor.monitoringDidChange() }
        }
        publish()
    }

    /// "Check Now".
    public func checkNow() {
        KarmaCallbackQueue.queue.async { [monitor] in monitor.pollNow() }
    }

    /// Chooses the scan depth for newly watched repositories ("Scan depth:" items).
    public func setDepth(_ value: String) throws {
        guard let depth = PRKind.Depth(rawValue: value) else {
            throw KarmaServiceError.invalid("Unknown scan depth \"\(value)\".")
        }
        PRStore.shared.defaultDepth = depth
        publish()
    }

    /// Chooses how new pull requests are announced ("Alert me about new PRs:" items).
    public func setNotifyStyle(_ value: String) throws {
        guard let style = PRKind.NotifyStyle(rawValue: value) else {
            throw KarmaServiceError.invalid("Unknown alert style \"\(value)\".")
        }
        PRStore.shared.notifyStyle = style
        publish()
    }

    /// Drops a pull request from the watch list and keeps it out of future alerts ("Ignore").
    public func dismiss(repoID: String, prID: Int) throws {
        let item = try find(repoID: repoID, prID: prID)
        KarmaCallbackQueue.queue.async { [monitor] in monitor.dismiss(item) }
    }

    /// Called after a repository was added, changed or removed, so the poll is redone. A newly added
    /// repository is muted for that poll: the pull requests already open on it are not news.
    public func repositoriesDidChange(mutedRepoIDs: Set<String> = []) {
        KarmaCallbackQueue.queue.async { [monitor] in
            monitor.silenceFirstPoll(for: mutedRepoIDs)
            monitor.pollNow()
        }
    }

    /// True while a review's checkout is open, so the repositories dialog refuses to clear the cache.
    public var hasActiveReview: Bool {
        workspace.read { $0.reviewSession != nil }
    }

    private func find(repoID: String, prID: Int) throws -> PRActionItem {
        lock.lock()
        let item = items.first { $0.repo.id == repoID && $0.pr.id == prID }
        lock.unlock()
        guard let item else {
            throw KarmaServiceError.notFound("That pull request is no longer in the watch list.")
        }
        return item
    }

    // MARK: - Opening a review

    /// Materialises a pull request on disk and opens it as the project (`PRReviewCoordinator.startReview`).
    /// Returns the id of the job that prepares it; the job's result is the new `PRStateDTO`, and
    /// `pr.review` is posted when the review is open.
    public func startReview(repoID: String, prID: Int) throws -> String {
        guard Self.gitIsAvailable else { throw KarmaServiceError.invalid(GitRunner.unavailableMessage) }
        let item = try find(repoID: repoID, prID: prID)

        lock.lock()
        if let running = preparingJob, jobs.job(running)?.status == "running" {
            lock.unlock()
            throw KarmaServiceError.busy("A pull request review is already being prepared.")
        }
        lock.unlock()

        // Only one review at a time: two checkouts would otherwise fight over the tree and the scan window.
        workspace.read { $0.reviewSession }?.tearDown()

        let target = monitor.workspaceURL(for: item.pr, repo: item.repo)
        let localPath = item.repo.localPath.map { URL(fileURLWithPath: $0) }
        let id = jobs.start(kind: "pr-review") { [self] context in
            // git needs the same credential the REST API does: a private repository cloned without one makes
            // git ask for a username on a terminal this process does not have.
            let auth = GitAuth(provider: item.repo.provider, token: PRStore.shared.token(for: item.repo) ?? "")
            let checkout = try GitRunner.prepare(repo: item.repo,
                                                 pr: item.pr,
                                                 workspace: target,
                                                 depth: item.repo.depth,
                                                 localPath: localPath,
                                                 auth: auth.token.isEmpty ? nil : auth,
                                                 progress: { stage, fraction in
                context.progress(done: Int((max(0, min(1, fraction)) * 100).rounded()), total: 100, stage: stage)
            })
            // The user pressed Cancel: drop the checkout rather than opening a review they dismissed.
            if context.isCancelled {
                GitRunner.cleanup(target, localPath: localPath)
                return nil
            }
            try openReview(PRReviewSession(repo: item.repo, pr: item.pr, checkout: checkout))
            return KarmaJSON.data(state())
        }
        lock.lock()
        preparingJob = id
        lock.unlock()
        return id
    }

    /// Shows a prepared checkout as the project (`MainWindowController.openPullRequestReview`): the tree is
    /// pruned to the changed files and carries their A/M badges.
    func openReview(_ session: PRReviewSession) throws {
        let previous = workspace.modify { state -> PRReviewSession? in
            let previous = state.reviewSession
            state.reviewSession = nil
            return previous
        }
        if let previous, previous !== session { previous.tearDown() }
        try workspace.open(root: session.workspace.path)
        workspace.modify { state in
            state.reviewSession = session
            state.prChangedPaths = session.reviewablePaths
            state.changeBadges = session.fileBadges
            state.showAllFiles = false
        }
        bus.post("pr.review", PRReviewEvent(state: "opened"))
        publish()
    }

    // MARK: - Inside a review

    private func requireSession() throws -> PRReviewSession {
        guard let session = workspace.read({ $0.reviewSession }) else {
            throw KarmaServiceError.invalid("No pull request review is open.")
        }
        return session
    }

    /// "Show All Files": lifts the pruning of the tree. The button disappears afterwards.
    public func showAllFiles() throws {
        _ = try requireSession()
        workspace.modify { $0.showAllFiles = true }
        publish()
    }

    /// The question asked before "Run a Scan".
    public func scanPrompt() -> PRScanPromptDTO {
        let client = OpenRouterClient.shared
        let message = """
            The built-in scan always runs on both the pull request and its base commit, so new problems can be \
            told apart from inherited ones.

            An AI pass reviews the changed code with \(client.selectedModel) (\(client.provider.name)). This \
            sends that code to your provider and consumes tokens unless you use a local model.

            Reviewing the base commit as well doubles the AI cost, and is only worth it when you want inherited \
            code judged by the same detector that judged the new code.

            How much should the AI review?
            """
        return PRScanPromptDTO(
            title: "Run an AI scan on this pull request?",
            message: message,
            choices: [
                PRChoiceDTO(value: "headOnly", title: "Pull request only (1 pass)", explanation: nil, selected: true),
                PRChoiceDTO(value: "both", title: "Pull request and base (2 passes)", explanation: nil, selected: false),
                PRChoiceDTO(value: "none", title: "Regular scan only", explanation: nil, selected: false)
            ])
    }

    /// "Run a Scan": scans the pull request and its base commit, then classifies the findings. `scope` is one of
    /// the `scanPrompt` choices. Returns the scan job's id; the rows are `SecurityScanService.state()`.
    public func scan(scope: String, ignoreAICache: Bool = false) throws -> String {
        let session = try requireSession()
        guard ["headOnly", "both", "none"].contains(scope) else {
            throw KarmaServiceError.invalid("Unknown scan scope \"\(scope)\".")
        }
        return SecurityScanService.shared.startPullRequestReview(session,
                                                                 wantsAI: scope != "none",
                                                                 wantsAIBase: scope == "both",
                                                                 ignoreAICache: ignoreAICache)
    }

    /// "Show Changes…": every changed file's patch.
    public func changes() throws -> PRChangesDTO {
        let session = try requireSession()
        let files = session.changedFiles.filter { $0.kind != .deleted }.map { file in
            PRChangedFileDTO(path: file.path,
                             absolutePath: session.workspace.appendingPathComponent(file.path).path,
                             title: "\(file.kind.badge)  \(file.path)\(file.kind == .added ? " (added)" : "")",
                             summary: PRDiffSummary.summary(for: file),
                             lines: Self.lines(of: file.patch))
        }
        return PRChangesDTO(windowTitle: "Pull Request Changes",
                            files: files,
                            emptyTitle: "No reviewable changes",
                            emptyMessage: "This pull request has no reviewable file changes.")
    }

    static func lines(of patch: String) -> [PRDiffLineDTO] {
        patch.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let line = String(raw)
            let kind: String
            if line.hasPrefix("@@") {
                kind = "hunk"
            } else if line.hasPrefix("+") {
                kind = "added"
            } else if line.hasPrefix("-") {
                kind = "removed"
            } else if line.hasPrefix("index ") || line.hasPrefix("Binary ") {
                kind = "meta"
            } else {
                kind = "context"
            }
            return PRDiffLineDTO(text: line,
                                 kind: kind,
                                 suspicious: line.hasPrefix("+") && SuspiciousLine.isSuspicious(String(line.dropFirst())))
        }
    }

    /// "Report…": the Markdown report with the pre-existing and fixed findings included.
    public func report() throws -> PRReportDTO {
        let session = try requireSession()
        return PRReportDTO(windowTitle: "Pull Request Review Report",
                           markdown: PRMarkdownReport.generate(session: session,
                                                               includePreExisting: true,
                                                               includeFixed: true),
                           suggestedName: session.reportFileName,
                           statusText: "Nothing has been sent anywhere. Save or copy this yourself.",
                           saveMessage: "Save the Markdown review report")
    }

    /// "Close Review": returns to an empty window and removes the checkout
    /// (`MainWindowController.leavePullRequestReview`).
    public func leaveReview(removeCheckout: Bool = true) {
        let session = workspace.modify { state -> PRReviewSession? in
            let session = state.reviewSession
            state.reviewSession = nil
            state.prChangedPaths = nil
            state.changeBadges = [:]
            state.showAllFiles = false
            return session
        }
        guard session != nil else { return }
        workspace.close()
        reviewEnded(session, removeCheckout: removeCheckout)
    }

    /// Everything that follows a review ending, whichever way it ended. Also called by the workspace when a
    /// different project is opened while a review is on screen.
    func reviewEnded(_ session: PRReviewSession?, removeCheckout: Bool = true) {
        guard let session else { return }
        SecurityScanService.shared.clearPullRequestReview()
        session.cancelScan()
        if removeCheckout { session.tearDown() }
        bus.post("pr.review", PRReviewEvent(state: "closed"))
        publish()
    }

    // MARK: - Alerts

    /// At most `maxAlertsPerPoll` alerts, most recently updated first (`PRNotifier.deliver`). The text always
    /// says how many pull requests arrived, so a capped batch cannot be mistaken for the whole story.
    static func notifications(for fresh: [PRActionItem]) -> [PRNotificationDTO] {
        guard !fresh.isEmpty else { return [] }
        let sorted = fresh.sorted {
            ($0.pr.updatedAt ?? .distantPast) > ($1.pr.updatedAt ?? .distantPast)
        }
        let shown = sorted.prefix(maxAlertsPerPoll)
        let total = sorted.count
        return shown.map { item in
            let headline = "#\(item.pr.number) \(item.pr.title) \u{2014} \(item.pr.author)"
            let body: String
            if total <= 1 {
                body = headline
            } else if total > shown.count {
                body = "\(headline)\n\(total) new since you last looked \u{2014} \(shown.count) most recent shown, "
                    + "the rest are in the watch list."
            } else {
                body = "\(headline)\n\(total) new since you last looked."
            }
            return PRNotificationDTO(repoID: item.repo.id, prID: item.pr.id,
                                     title: "\(item.repo.repoSlug) #\(item.pr.number)", body: body)
        }
    }
}

extension PRService: PRMonitorPresenter {
    /// The browser asks for notification permission itself.
    func requestNotificationAuthorization() {}

    func deliver(_ fresh: [PRActionItem], allowSound: Bool) {
        let alerts = Self.notifications(for: fresh)
        guard !alerts.isEmpty else { return }
        bus.post("pr.notify", PRNotifyEvent(items: alerts, allowSound: allowSound))
    }

    /// A review requested from a notification while the server was down cannot be resumed: nothing parks it.
    func consumePendingReview(among items: [PRActionItem]) -> PRActionItem? { nil }

    func startReview(_ item: PRActionItem) {
        _ = try? startReview(repoID: item.repo.id, prID: item.pr.id)
    }
}
