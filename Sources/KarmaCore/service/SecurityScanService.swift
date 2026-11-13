// by cipher.org.uk
import Foundation

/// The Security Scan window (`ScanWindowController`) without its drawing: the
/// scan and AI phases, the ignore list, sorting, SARIF export, AI triage, and the
/// pull-request review variant with its "In PR?" column.
///
/// There is one scan window, so there is one scan state. Changes to it are
/// announced with the `scan.changed` event; a front end then fetches `state()`.
public final class SecurityScanService: @unchecked Sendable {
    public static let shared = SecurityScanService()

    // MARK: - Data

    /// One row of the results table.
    public struct FindingDTO: Codable, Sendable {
        /// `"<path>#<line>"`, the key the ignore list and the triage column use.
        public var key: String
        public var path: String
        /// Path relative to the scanned folder (the File column).
        public var displayPath: String
        public var line: Int
        public var function: String
        public var category: String
        /// The finding text before the window's decoration (flow prefix, unreachable note).
        public var message: String
        public var taintPath: String?
        /// "Critical", "High", "Medium" or "Low".
        public var severity: String
        /// 3 (critical) to 0 (low).
        public var severityRank: Int
        public var exploitability: String
        public var exploitabilityRank: Int
        public var reachable: Bool
        public var crossFile: Bool
        /// The Engine column: "AST", "Heuristic", "AI", or several joined by ", ".
        public var engine: String
        /// "introduced", "contextual", "preExisting" or "fixed" during a pull request review.
        public var awareness: String?
        /// The AI triage verdict: true = valid issue, false = not a valid issue, nil = not checked.
        public var triage: Bool?
    }

    /// A message the window shows in an alert. `id` increases with every alert so a front end shows each once.
    public struct NoticeDTO: Codable, Sendable {
        public var id: Int
        public var title: String
        public var message: String
    }

    public struct StateDTO: Codable, Sendable {
        /// The window title: "Security Scan", or the pull request's title while reviewing one.
        public var title: String
        /// The status line.
        public var status: String
        /// True while the status line is the "AI phase: reviewing the code…" text (purple and green).
        public var statusIsAIPhase: Bool
        /// The progress bar value 0...1, or nil when the bar is hidden.
        public var progress: Double?
        public var progressIndeterminate: Bool
        /// The "(thinking)" indicator.
        public var aiThinking: Bool
        public var rows: [FindingDTO]
        /// The "In PR?" column is shown (a pull request review is open).
        public var showPullRequestColumn: Bool
        /// The Triage column is shown (a triage pass ran or is running).
        public var showTriageColumn: Bool
        /// The Rescan button is enabled.
        public var canRescan: Bool
        /// The Export Scan button is enabled (there are rows).
        public var canExport: Bool
        /// The Triage (AI) button is enabled.
        public var canTriage: Bool
        public var triageRunning: Bool
        /// The save panel's message for Export Scan.
        public var exportMessage: String
        public var notice: NoticeDTO?
        /// The job of the scan or triage in progress, if any.
        public var jobId: String?
    }

    /// The question the Security Scanner button asks before scanning.
    public struct ScanPromptDTO: Codable, Sendable {
        public var message: String
        public var informative: String
        public var buttons: [String]
    }

    public struct SortKeyDTO: Codable, Sendable {
        public var key: String
        public var ascending: Bool

        public init(key: String, ascending: Bool) {
            self.key = key
            self.ascending = ascending
        }
    }

    // MARK: - State

    /// Extra attempts for a triage request that failed transiently.
    private static let maxTriageRetries = 2
    /// Delay before each triage retry (index = retry number - 1).
    private static let triageRetryDelays: [Double] = [2, 8]

    private let lock = NSLock()
    private let ignoreList = FindingIgnoreList(defaultsKey: "ScanWindowController.ignoredLines")
    private let bus = KarmaEventBus.shared
    private let jobs = KarmaJobCenter.shared

    /// Cached results so reopening the window does not re-scan the same folder.
    private var cachedFolder: URL?
    private var cachedFindings: [ScanFinding] = []

    private var findings: [ScanFinding] = []
    private var scannedFolder: URL?
    private var sortKeys: [SortKeyDTO] = []
    private var status = "No scan has been run yet."
    private var statusIsAIPhase = false
    private var progress: Double?
    private var progressIndeterminate = false
    private var aiThinking = false
    private var aiPhaseActive = false
    private var rescanEnabled = true
    private var scanCancelled = false
    private var wantsAI = false
    private var wantsAIBase = false
    private var currentJob: String?
    private var notice: NoticeDTO?
    private var noticeCounter = 0

    // Pull request review mode.
    private var prSession: PRReviewSession?
    private var prAwareness: [String: DiffAwareness] = [:]

    // Triage.
    private var triageVerdicts: [String: Bool] = [:]
    private var triageRows: [ScanFinding] = []
    private var triageIndex = 0
    private var triageChecked = 0
    private var triageInFlight = 0
    private var triageFailed = 0
    private var triageRunning = false
    private var triageCancelled = false
    private var triageColumnVisible = false
    private var triageDone: DispatchSemaphore?

    private var lastEvent = Date.distantPast

    init() {}

    // MARK: - Reading the state

    public func state() -> StateDTO {
        lock.lock()
        defer { lock.unlock() }
        return stateLocked()
    }

    private func stateLocked() -> StateDTO {
        let rows = findings.map { row($0) }
        return StateDTO(
            title: prSession.map { "Karma Pro \u{2014} \($0.title)" } ?? "Security Scan",
            status: status,
            statusIsAIPhase: statusIsAIPhase,
            progress: progress,
            progressIndeterminate: progressIndeterminate,
            aiThinking: aiThinking,
            rows: rows,
            showPullRequestColumn: prSession != nil,
            showTriageColumn: triageColumnVisible,
            canRescan: rescanEnabled,
            canExport: !findings.isEmpty,
            canTriage: triageButtonEnabledLocked(),
            triageRunning: triageRunning,
            exportMessage: "Exports the \(findings.count) finding\(findings.count == 1 ? "" : "s") "
                + "shown in the table, with absolute file paths.",
            notice: notice,
            jobId: currentJob)
    }

    private func row(_ finding: ScanFinding) -> FindingDTO {
        let key = FindingIgnoreList.key(for: finding)
        let awareness: String?
        switch prAwareness[key] {
        case .some(.introduced): awareness = "introduced"
        case .some(.contextual): awareness = "contextual"
        case .some(.preExisting): awareness = "preExisting"
        case .some(.fixed): awareness = "fixed"
        case .none: awareness = nil
        }
        return FindingDTO(key: key,
                          path: finding.fileURL.path,
                          displayPath: displayPath(for: finding),
                          line: finding.line,
                          function: finding.function,
                          category: finding.category,
                          message: finding.message,
                          taintPath: finding.taintPath,
                          severity: finding.severity.label,
                          severityRank: finding.severity.rawValue,
                          exploitability: finding.exploitability.label,
                          exploitabilityRank: finding.exploitability.rawValue,
                          reachable: finding.reachable,
                          crossFile: finding.crossFile,
                          engine: finding.scanningSource,
                          awareness: awareness,
                          triage: triageVerdicts[key])
    }

    /// The file as the reader knows it: its path relative to the scanned folder.
    private func displayPath(for finding: ScanFinding) -> String {
        let path = finding.fileURL.standardizedFileURL.path
        if let root = scannedFolder?.standardizedFileURL.path, path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
        return finding.fileURL.lastPathComponent
    }

    /// Posts `scan.changed`. Progress updates are limited to one per 250 ms; `force` always posts.
    private func changed(force: Bool = true) {
        let now = Date()
        lock.lock()
        let due = force || now.timeIntervalSince(lastEvent) >= 0.25
        if due { lastEvent = now }
        lock.unlock()
        if due { bus.post("scan.changed") }
    }

    // MARK: - Starting a scan

    /// What the Security Scanner button asks first (`securityScanClicked`).
    public func scanPrompt() throws -> ScanPromptDTO {
        _ = try KarmaWorkspace.shared.requireRoot()
        let client = OpenRouterClient.shared
        return ScanPromptDTO(
            message: "Also run an AI scan?",
            informative: "Run the built-in security scan first, then ask \(client.selectedModel) (\(client.provider.name)) to audit the code for additional vulnerabilities.\n\nThis sends your project's source code to the AI model and consumes tokens / credits from your AI account (unless you use Ollama and a local model). Results are cached locally.\n\nInclude the AI scan?",
            buttons: ["Yes, analyse with AI", "Regular scan only"])
    }

    /// `ScanWindowController.load(folder:wantsAI:)`: shows the cached scan of the open project when no AI
    /// pass is wanted, otherwise scans. Returns the job id (the cached case returns an already finished job).
    @discardableResult
    public func start(wantsAI: Bool, ignoreAICache: Bool = false) throws -> String {
        guard let folder = KarmaWorkspace.shared.read({ $0.root }) else {
            throw KarmaServiceError.noProject
        }
        // Scanning a plain folder ends any pull-request review and any triage of old rows.
        clearPullRequestReview()
        cancelTriage()
        lock.lock()
        self.wantsAI = wantsAI
        scannedFolder = folder
        rescanEnabled = false
        let cached = cachedFolder?.standardizedFileURL == folder.standardizedFileURL ? cachedFindings : nil
        lock.unlock()

        if !wantsAI, let cached {
            let id = jobs.start(kind: "scan") { _ in nil }
            lock.lock()
            aiPhaseActive = false
            aiThinking = false
            findings = ignoreList.apply(cached)
            applySortingLocked()
            resetTriageLocked()
            rescanEnabled = true
            status = cached.isEmpty
                ? "Cached scan (no issues found) \u{2014} Rescan to refresh."
                : "Showing cached scan: \(cached.count) potential issue\(cached.count == 1 ? "" : "s") \u{2014} Rescan to refresh."
            currentJob = id
            lock.unlock()
            changed()
            return id
        }
        return performScan(folder: folder, ignoreAICache: ignoreAICache)
    }

    /// Rescan: a pull-request review re-runs the paired head and base scan; a project scan re-runs the
    /// single pass without serving cached AI results.
    @discardableResult
    public func rescan() throws -> String {
        lock.lock()
        let session = prSession
        let folder = scannedFolder
        let aiWanted = wantsAI
        lock.unlock()
        if let session {
            session.cancelScan()
            return startPullRequestReview(session, wantsAI: aiWanted, wantsAIBase: false, ignoreAICache: true)
        }
        guard let folder else { throw KarmaServiceError.invalid("No scan has been run yet.") }
        return performScan(folder: folder, ignoreAICache: true)
    }

    /// Stops a running scan or triage (what closing the window does).
    public func cancel() {
        lock.lock()
        scanCancelled = true
        let job = currentJob
        let session = prSession
        lock.unlock()
        session?.cancelScan()
        cancelTriage()
        if let job { jobs.cancel(job) }
    }

    private func performScan(folder: URL, ignoreAICache: Bool) -> String {
        // A fresh scan supersedes any triage pass over the previous rows.
        cancelTriage()
        lock.lock()
        resetTriageLocked()
        status = "Scanning \(folder.lastPathComponent)\u{2026}"
        statusIsAIPhase = false
        progress = 0
        progressIndeterminate = true
        scanCancelled = false
        aiPhaseActive = false
        rescanEnabled = false
        let aiWanted = wantsAI
        lock.unlock()

        let id = jobs.start(kind: "scan") { [self] context in
            let sourceIndex = KarmaWorkspace.shared.read { state -> ProjectSourceIndex? in
                state.sourceIndex?.root == folder.standardizedFileURL ? state.sourceIndex : nil
            }
            let result = VulnerabilityScanner.scan(
                projectRoot: folder,
                progress: { done, total in
                    let fraction = total > 0 ? Double(done) / Double(total) : 0
                    self.lock.lock()
                    self.progressIndeterminate = false
                    // The heuristic phase fills the whole bar, or the first 40% when an AI pass follows.
                    self.progress = fraction * (aiWanted ? 0.4 : 1.0)
                    self.lock.unlock()
                    context.progress(done: Int(fraction * 1000), total: 1000, stage: "Scanning")
                    self.changed(force: false)
                },
                isCancelled: { [self] in context.isCancelled || cancelledFlag() },
                sourceIndex: sourceIndex)

            if context.isCancelled || cancelledFlag() {
                finishCancelledScan()
                return nil
            }
            lock.lock()
            cachedFolder = folder
            cachedFindings = result
            progress = aiWanted ? 0.4 : nil
            progressIndeterminate = false
            findings = ignoreList.apply(result)
            applySortingLocked()
            updateStatusLocked(totalCount: result.count, aiCount: 0)
            if !aiWanted { rescanEnabled = true }
            lock.unlock()
            changed()
            if aiWanted {
                runAIPhase(folder: folder, heuristic: result, ignoreCache: ignoreAICache, context: context)
            }
            return KarmaJSON.data(state())
        }
        lock.lock()
        currentJob = id
        lock.unlock()
        changed()
        return id
    }

    private func cancelledFlag() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return scanCancelled
    }

    private func finishCancelledScan() {
        lock.lock()
        status = "Scan cancelled."
        progress = nil
        progressIndeterminate = false
        aiThinking = false
        aiPhaseActive = false
        rescanEnabled = true
        lock.unlock()
        changed()
    }

    /// Runs the AI discovery pass, scaling its progress over the remaining 60% of the bar and merging any
    /// additional findings. Blocks until the pass is over. The user authorised token use at the Security
    /// Scanner button; the API key check is the only gate.
    private func runAIPhase(folder: URL, heuristic: [ScanFinding], ignoreCache: Bool, context: JobContext) {
        let client = OpenRouterClient.shared
        let providerName = client.provider.name

        guard !client.requiresAPIKey || !client.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lock.lock()
            noticeCounter += 1
            notice = NoticeDTO(id: noticeCounter, title: "AI scan unavailable",
                               message: "AI scan needs a model connected. Open the AI Assistant window, choose \(providerName), add your API key, and connect, then re-run the scan.")
            updateStatusLocked(totalCount: heuristic.count, aiCount: 0, aiSkipped: true)
            progress = nil
            rescanEnabled = true
            lock.unlock()
            changed()
            return
        }

        lock.lock()
        status = "AI phase: reviewing the code\u{2026}"
        statusIsAIPhase = true
        progress = 0.4
        progressIndeterminate = false
        aiPhaseActive = true
        lock.unlock()
        changed()

        let finished = DispatchSemaphore(value: 0)
        AISecurityScanner.runAI(
            projectRoot: folder,
            existingFindings: heuristic,
            progress: { [self] fraction in
                lock.lock()
                // The bar fills the remaining 0.4 to 1.0.
                progress = 0.4 + 0.6 * min(fraction, 1)
                lock.unlock()
                context.progress(done: Int(progress.map { $0 * 1000 } ?? 0), total: 1000, stage: "AI scan")
                changed(force: false)
            },
            isCancelled: { [self] in context.isCancelled || cancelledFlag() },
            completion: { [self] result in
                lock.lock()
                aiPhaseActive = false
                aiThinking = false
                statusIsAIPhase = false
                if scanCancelled || context.isCancelled {
                    lock.unlock()
                    finishCancelledScan()
                    finished.signal()
                    return
                }
                // A vulnerability both engines found is one row whose engine column names both.
                let merged = result.findings
                cachedFindings = merged
                findings = ignoreList.apply(merged)
                applySortingLocked()
                resetTriageLocked()
                progress = nil
                updateStatusLocked(totalCount: merged.count,
                                   aiCount: merged.filter { ScanFindingSort.isAIRow($0) }.count,
                                   aiCancelled: result.cancelled,
                                   aiIssues: result.errors)
                rescanEnabled = true
                lock.unlock()
                changed()
                finished.signal()
            },
            onPhase: { [self] phase in
                lock.lock()
                if aiPhaseActive && !scanCancelled { aiThinking = (phase == .thinking) }
                lock.unlock()
                changed(force: false)
            },
            ignoreCache: ignoreCache)
        finished.wait()
    }

    private func updateStatusLocked(totalCount: Int,
                                    aiCount: Int,
                                    aiSkipped: Bool = false,
                                    aiCancelled: Bool = false,
                                    aiIssues: [String] = []) {
        statusIsAIPhase = false
        let plural = { (n: Int) in n == 1 ? "" : "s" }
        if totalCount == 0 {
            status = aiSkipped
                ? "Scan complete: no issues found. (AI analysis skipped \u{2014} no source files were reported.)"
                : "Scan complete: no issues found."
            return
        }
        var text = "Scan complete: \(totalCount) potential issue\(plural(totalCount)) found"
        if aiCount > 0 { text += " (\(aiCount) via AI)" }
        if aiSkipped {
            text += " \u{2014} AI analysis skipped"
        } else if aiCancelled {
            text += " \u{2014} AI analysis cancelled"
        }
        if !aiIssues.isEmpty {
            text += " (\(aiIssues.count) AI chunk\(plural(aiIssues.count)) skipped: \(aiIssues.prefix(3).joined(separator: "; ")))"
        }
        status = text + "."
    }

    // MARK: - Sorting, ignoring, export

    /// Sets the sort order (the table's sort descriptors) and re-sorts the rows.
    public func setSort(_ keys: [SortKeyDTO]) {
        lock.lock()
        sortKeys = keys
        applySortingLocked()
        lock.unlock()
        changed()
    }

    private func applySortingLocked() {
        guard !sortKeys.isEmpty else { return }
        let current = sortKeys
        findings.sort { a, b in
            for descriptor in current {
                let result = ScanFindingSort.compare(a, b, key: descriptor.key, ascending: descriptor.ascending)
                if result != .orderedSame { return result == .orderedAscending }
            }
            return false
        }
    }

    /// "Ignore issue": hides the finding and remembers that across sessions.
    public func ignore(key: String) throws {
        lock.lock()
        guard let finding = findings.first(where: { FindingIgnoreList.key(for: $0) == key }) else {
            lock.unlock()
            throw KarmaServiceError.notFound("That finding is no longer in the table.")
        }
        ignoreList.ignore(finding)
        findings = ignoreList.apply(findings)
        lock.unlock()
        changed()
    }

    /// "Export Scan": the rows shown, as SARIF 2.1.0 with absolute paths.
    public func export() throws -> (fileName: String, data: Data) {
        lock.lock()
        let rows = findings
        lock.unlock()
        guard !rows.isEmpty else { throw KarmaServiceError.invalid("There are no findings to export.") }
        return ("KarmaPro-scan.sarif.json", try SARIFExport.data(from: rows))
    }

    // MARK: - Triage (AI)

    private func triageButtonEnabledLocked() -> Bool {
        OpenRouterClient.shared.isConfigured && !findings.isEmpty && !triageRunning
    }

    /// The confirmation the Triage (AI) button asks.
    public func triagePrompt() -> ScanPromptDTO {
        let client = OpenRouterClient.shared
        return ScanPromptDTO(
            message: "Triage with AI",
            informative: "Triage is 60-80% accurate depending on the model used, so it is recommended to also verify the results.\n\nEvery finding in the table will be checked with \(client.selectedModel) (\(client.provider.name)). This sends the finding details to the AI model and consumes tokens / credits from your AI account (unless you use Ollama and a local model).",
            buttons: ["Triage", "Cancel"])
    }

    /// Starts checking every finding with the AI model, several at a time (the provider's limit).
    /// Returns the job id.
    public func startTriage() throws -> String {
        lock.lock()
        // rescanEnabled is false exactly while a scan / AI phase is running.
        guard !triageRunning, !findings.isEmpty, rescanEnabled else {
            lock.unlock()
            throw KarmaServiceError.busy("A scan or triage is already running, or there are no findings to check.")
        }
        guard OpenRouterClient.shared.isConfigured else {
            lock.unlock()
            throw KarmaServiceError.invalid("Connect an AI model in the AI Assistant window first.")
        }
        triageRows = findings
        triageRunning = true
        triageCancelled = false
        triageIndex = 0
        triageChecked = 0
        triageInFlight = 0
        triageFailed = 0
        triageVerdicts.removeAll()
        rescanEnabled = false
        triageColumnVisible = true
        progress = 0
        progressIndeterminate = false
        status = "Triage: 0/\(triageRows.count) checked\u{2026}"
        let done = DispatchSemaphore(value: 0)
        triageDone = done
        lock.unlock()
        changed()

        let id = jobs.start(kind: "triage") { [self] _ in
            triageNext()
            done.wait()
            return KarmaJSON.data(state())
        }
        lock.lock()
        currentJob = id
        lock.unlock()
        return id
    }

    /// Keeps up to the provider's limit of requests in flight; each completion re-enters here.
    private func triageNext() {
        let client = OpenRouterClient.shared
        let model = client.selectedModel
        let limit = client.provider.maxConcurrentRequests
        var dispatch: [ScanFinding] = []
        var finish = false
        lock.lock()
        guard triageRunning, !triageCancelled else {
            lock.unlock()
            return
        }
        while triageInFlight < limit && triageIndex < triageRows.count {
            dispatch.append(triageRows[triageIndex])
            triageIndex += 1
            triageInFlight += 1
        }
        if triageInFlight == 0 && triageIndex >= triageRows.count { finish = true }
        lock.unlock()
        for finding in dispatch { triageOne(finding, model: model, attempt: 0) }
        if finish { finishTriage() }
    }

    /// Checks one finding. A transient transport failure is retried (up to `maxTriageRetries`); a model
    /// that answered something other than VALID/INVALID is not retried.
    private func triageOne(_ finding: ScanFinding, model: String, attempt: Int) {
        OpenRouterClient.shared.sendChat(
            systemPrompt: ScanTriage.systemPrompt,
            userPrompt: ScanTriage.prompt(for: finding),
            model: model,
            scope: .scanner) { [self] result in
            lock.lock()
            guard triageRunning else {
                lock.unlock()
                return
            }
            switch result {
            case .success(let text):
                triageInFlight -= 1
                triageChecked += 1
                if let verdict = ScanTriage.parseVerdict(text) {
                    triageVerdicts[FindingIgnoreList.key(for: finding)] = verdict
                } else {
                    triageFailed += 1
                }
            case .failure(let error):
                if ScanTriage.isTransientFailure(error), attempt < Self.maxTriageRetries {
                    // The slot stays occupied: the row is still being checked.
                    let delay = Self.triageRetryDelays[min(attempt, Self.triageRetryDelays.count - 1)]
                    lock.unlock()
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
                        lock.lock()
                        let go = triageRunning && !triageCancelled
                        lock.unlock()
                        if go { triageOne(finding, model: model, attempt: attempt + 1) }
                    }
                    return
                }
                triageInFlight -= 1
                triageChecked += 1
                triageFailed += 1
            }
            progress = Double(triageChecked) / Double(triageRows.count)
            status = "Triage: \(triageChecked)/\(triageRows.count) checked\u{2026}"
            lock.unlock()
            changed(force: false)
            triageNext()
        }
    }

    private func finishTriage() {
        lock.lock()
        guard triageRunning else {
            lock.unlock()
            return
        }
        let wasCancelled = triageCancelled
        let total = triageRows.count
        let checked = triageChecked
        let failed = triageFailed
        triageRunning = false
        triageCancelled = false
        triageInFlight = 0
        rescanEnabled = true
        progress = nil
        if wasCancelled {
            status = "Triage cancelled \u{2014} \(checked)/\(total) checked."
        } else if failed > 0 {
            status = "Triage complete: \(checked)/\(total) checked (\(failed) failed)."
        } else {
            status = "Triage complete: \(checked)/\(total) checked."
        }
        let done = triageDone
        triageDone = nil
        lock.unlock()
        changed()
        done?.signal()
    }

    /// Stops a triage in flight (a new scan, a pull request switch, closing the window).
    public func cancelTriage() {
        lock.lock()
        guard triageRunning else {
            lock.unlock()
            return
        }
        triageCancelled = true
        lock.unlock()
        finishTriage()
    }

    /// Clears verdicts and hides the column when a new set of rows arrives.
    private func resetTriageLocked() {
        guard !triageRunning else { return }
        triageVerdicts.removeAll()
        triageColumnVisible = false
    }

    // MARK: - Pull request review

    /// `loadPullRequestReview`: scans the pull request and its base, then shows every finding with the
    /// "In PR?" column. Returns the job id.
    @discardableResult
    func startPullRequestReview(_ session: PRReviewSession, wantsAI: Bool, wantsAIBase: Bool, ignoreAICache: Bool) -> String {
        cancelTriage()
        lock.lock()
        prSession = session
        self.wantsAI = wantsAI
        self.wantsAIBase = wantsAIBase
        // The folder cache must not be reused: a normal scan of the same workspace would overwrite the
        // classified results with plain ones.
        scannedFolder = nil
        rescanEnabled = false
        status = "Reviewing \(session.context.pr.number)\u{2026}"
        statusIsAIPhase = false
        progress = nil
        progressIndeterminate = true
        scanCancelled = false
        lock.unlock()

        let id = jobs.start(kind: "scan") { [self] context in
            let finished = DispatchSemaphore(value: 0)
            session.scan(wantsAI: wantsAI, wantsAIBase: wantsAIBase, ignoreAICache: ignoreAICache,
                         progress: { [self] message in
                lock.lock()
                status = message
                lock.unlock()
                changed(force: false)
            }, completion: { [self] completed in
                lock.lock()
                progressIndeterminate = false
                progress = nil
                rescanEnabled = completed
                if completed {
                    // The same post-processing a project scan gets, so the two tables read alike.
                    findings = ignoreList.apply(session.findings.map(\.finding))
                    applySortingLocked()
                    rebuildAwarenessLocked()
                    resetTriageLocked()
                    updatePRStatusLocked()
                } else {
                    status = "Review cancelled."
                }
                lock.unlock()
                changed()
                finished.signal()
            })
            // A cancel request reaches the session through `cancel()`.
            while finished.wait(timeout: .now() + 0.2) == .timedOut {
                if context.isCancelled { session.cancelScan() }
            }
            return KarmaJSON.data(state())
        }
        lock.lock()
        currentJob = id
        lock.unlock()
        changed()
        return id
    }

    private func rebuildAwarenessLocked() {
        guard let session = prSession else {
            prAwareness.removeAll()
            return
        }
        prAwareness = Dictionary(session.findings.map {
            (FindingIgnoreList.key(for: $0.finding), $0.awareness)
        }, uniquingKeysWith: { first, _ in first })
    }

    private func updatePRStatusLocked() {
        guard let session = prSession else { return }
        let all = session.findings
        let introduced = DiffAwareClassifier.introduced(all).count
        let contextual = DiffAwareClassifier.contextual(all).count
        let preExisting = DiffAwareClassifier.preExisting(all).count
        let fixed = DiffAwareClassifier.fixed(all).count
        status = "PR #\(session.context.pr.number): \(introduced) new \u{00B7} \(contextual) touched \u{00B7} "
            + "\(preExisting) pre-existing \u{00B7} \(fixed) fixed"
    }

    /// Removes pull-request mode and returns to an ordinary project scan.
    func clearPullRequestReview() {
        lock.lock()
        let session = prSession
        prSession = nil
        prAwareness.removeAll()
        lock.unlock()
        session?.cancelScan()
        if session != nil { changed() }
    }
}
