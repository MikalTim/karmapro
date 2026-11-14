// by cipher.org.uk
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The update checks behind the Karma Pro menu items (`UpdateMenuTarget`): a manual
/// check, the opt-in daily check, and the outcome each check produces.
///
/// `UpdateChecker.check` delivers its result on the main queue, which the server never
/// services, so this service makes the same GitHub request itself and reads the reply
/// with `UpdateChecker.interpret`. Nothing here opens a page: the browser opens `downloadURL`.
public enum UpdateService {

    // MARK: - DTOs

    /// The outcome a check presents: the alert's title and message, plus the release details.
    public struct UpdateOutcomeDTO: Codable, Sendable {
        /// "upToDate", "updateAvailable" or "failed".
        public var kind: String
        public var title: String
        public var message: String
        /// The newer version, for "updateAvailable" only.
        public var version: String?
        public var publishedAt: Date?
        /// Where Download goes.
        public var downloadURL: String

        public init(kind: String, title: String, message: String, version: String?, publishedAt: Date?,
                    downloadURL: String) {
            self.kind = kind
            self.title = title
            self.message = message
            self.version = version
            self.publishedAt = publishedAt
            self.downloadURL = downloadURL
        }
    }

    /// The update state the menu and the `update.changed` event carry.
    public struct UpdateStateDTO: Codable, Sendable {
        public var currentVersion: String
        /// Whether the daily check is on.
        public var automaticChecks: Bool
        /// When the last check was attempted, whatever its result.
        public var lastCheckedAt: Date?
        public var checkRunning: Bool
        /// "Checking…" while a check runs, else "Check for Updates…".
        public var checkMenuTitle: String
        /// The newer release known from an earlier check, when it is newer than the running version.
        public var knownNewerVersion: String?
        /// "Update <version> Available" while `knownNewerVersion` is set; nil hides the menu row.
        public var availableMenuTitle: String?
        public var downloadURL: String
        /// The outcome of the last check made since the server started.
        public var lastOutcome: UpdateOutcomeDTO?

        public init(currentVersion: String, automaticChecks: Bool, lastCheckedAt: Date?, checkRunning: Bool,
                    checkMenuTitle: String, knownNewerVersion: String?, availableMenuTitle: String?,
                    downloadURL: String, lastOutcome: UpdateOutcomeDTO?) {
            self.currentVersion = currentVersion
            self.automaticChecks = automaticChecks
            self.lastCheckedAt = lastCheckedAt
            self.checkRunning = checkRunning
            self.checkMenuTitle = checkMenuTitle
            self.knownNewerVersion = knownNewerVersion
            self.availableMenuTitle = availableMenuTitle
            self.downloadURL = downloadURL
            self.lastOutcome = lastOutcome
        }
    }

    // MARK: - Shared state

    private static let lock = NSLock()
    private static var checking = false
    private static var checkJobID: String?
    private static var lastOutcome: UpdateOutcomeDTO?
    private static var installed = false
    /// Keeps the daily gate timer alive.
    private static var gateTimer: DispatchSourceTimer?

    /// How often the daily gate is consulted (the same five minutes as the menu target).
    private static let gateInterval: TimeInterval = 300

    // MARK: - Queries

    /// The current update state.
    public static func state() -> UpdateStateDTO {
        lock.lock()
        defer { lock.unlock() }
        return snapshot()
    }

    // MARK: - Actions

    /// Starts an update check and returns the id of the `update-check` job, whose result is an
    /// `UpdateOutcomeDTO`. A check already running is returned as is. With `manual` false the check
    /// starts only when the daily check is on and due; otherwise it throws.
    public static func check(manual: Bool) throws -> String {
        if !manual {
            lock.lock()
            let due = UpdateSettings.automaticChecksEnabled && UpdateSettings.isCheckDue()
            lock.unlock()
            guard due else {
                throw KarmaServiceError.invalid("Automatic checks are off, or no check is due yet.")
            }
        }
        let id = startCheck()
        postState()
        return id
    }

    /// Turns the daily check on or off (`toggleAutomaticChecks`). Turning it on checks at once if the gate allows.
    public static func setAutomatic(_ enabled: Bool) {
        lock.lock()
        UpdateSettings.automaticChecksEnabled = enabled
        lock.unlock()
        postState()
        runAutomaticCheckIfDue()
    }

    /// Starts the daily gate: a timer every five minutes, plus one immediate check. Safe to call twice.
    public static func install() {
        lock.lock()
        let first = !installed
        installed = true
        if first {
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            timer.schedule(deadline: .now() + gateInterval, repeating: gateInterval)
            timer.setEventHandler { runAutomaticCheckIfDue() }
            gateTimer = timer
            timer.resume()
        }
        lock.unlock()
        if first {
            runAutomaticCheckIfDue()
        }
    }

    // MARK: - Private

    /// Starts a check when the daily check is on and due. Only `install()` and `setAutomatic` call this.
    private static func runAutomaticCheckIfDue() {
        lock.lock()
        let due = UpdateSettings.automaticChecksEnabled && UpdateSettings.isCheckDue()
        lock.unlock()
        guard due else { return }
        _ = startCheck()
        postState()
    }

    /// Starts the `update-check` job, or returns the one already running.
    private static func startCheck() -> String {
        lock.lock()
        defer { lock.unlock() }
        if checking, let running = checkJobID {
            return running
        }
        checking = true
        let id = KarmaJobCenter.shared.start(kind: "update-check") { _ in
            let outcome = performCheck()
            lock.lock()
            // Recorded whatever the result, so a failure cannot retry in a loop.
            UpdateSettings.lastCheckDate = Date()
            switch outcome {
            case .upToDate(let current):
                UpdateSettings.clearKnownNewerVersionIfNotNewer(than: current)
            case .updateAvailable(let release):
                UpdateSettings.knownNewerVersion = release.version
            case .failed:
                break
            }
            let dto = describe(outcome)
            lastOutcome = dto
            checking = false
            checkJobID = nil
            lock.unlock()
            postState()
            return KarmaJSON.data(dto)
        }
        checkJobID = id
        return id
    }

    /// One GitHub request, read with the same rules `UpdateChecker` uses.
    private static func performCheck() -> UpdateChecker.Outcome {
        var request = URLRequest(url: UpdateChecker.endpoint)
        request.timeoutInterval = UpdateChecker.timeout
        request.setValue("KarmaPro/\(UpdateChecker.currentVersion) (update check)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        let reply = ReplyBox()
        URLSession.shared.dataTask(with: request) { data, response, _ in
            reply.set(data: data, response: response)
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + UpdateChecker.timeout + 5) == .success else {
            return .failed
        }
        let (data, response) = reply.get()
        return UpdateChecker.interpret(data: data, response: response)
    }

    /// The alert texts for an outcome, as `UpdateMenuTarget.apply` shows them.
    private static func describe(_ outcome: UpdateChecker.Outcome) -> UpdateOutcomeDTO {
        let download = UpdateChecker.downloadPage.absoluteString
        switch outcome {
        case .upToDate(let current):
            return UpdateOutcomeDTO(kind: "upToDate", title: "You're up to date",
                                    message: "Karma Pro \(current) is the latest release.",
                                    version: nil, publishedAt: nil, downloadURL: download)
        case .updateAvailable(let release):
            var message = "You have \(UpdateChecker.currentVersion)."
            let age = UpdateChecker.agePhrase(since: release.publishedAt)
            if !age.isEmpty { message += " Version \(release.version) was released \(age)." }
            return UpdateOutcomeDTO(kind: "updateAvailable", title: "Karma Pro \(release.version) Is Available",
                                    message: message, version: release.version,
                                    publishedAt: release.publishedAt, downloadURL: download)
        case .failed:
            return UpdateOutcomeDTO(kind: "failed", title: "Can't Currently Check for Updates",
                                    message: "Karma Pro couldn't check GitHub for a newer release.",
                                    version: nil, publishedAt: nil, downloadURL: download)
        }
    }

    /// Caller must hold `lock`.
    private static func snapshot() -> UpdateStateDTO {
        let current = UpdateChecker.currentVersion
        let known = UpdateSettings.knownNewerVersion
        let isNewer = known.map { VersionComparator.isNewer(tag: $0, than: current) } ?? false
        return UpdateStateDTO(
            currentVersion: current,
            automaticChecks: UpdateSettings.automaticChecksEnabled,
            lastCheckedAt: UpdateSettings.lastCheckDate,
            checkRunning: checking,
            checkMenuTitle: checking ? "Checking…" : "Check for Updates…",
            knownNewerVersion: isNewer ? known : nil,
            availableMenuTitle: isNewer ? known.map { "Update \($0) Available" } : nil,
            downloadURL: UpdateChecker.downloadPage.absoluteString,
            lastOutcome: lastOutcome)
    }

    /// Posts `update.changed` with the current state. Must not be called with `lock` held.
    private static func postState() {
        KarmaEventBus.shared.post("update.changed", state())
    }
}

/// Hands the reply of a `URLSession` task from its callback thread to the waiting job.
private final class ReplyBox {
    private let lock = NSLock()
    private var data: Data?
    private var response: URLResponse?

    func set(data: Data?, response: URLResponse?) {
        lock.lock()
        defer { lock.unlock() }
        self.data = data
        self.response = response
    }

    func get() -> (Data?, URLResponse?) {
        lock.lock()
        defer { lock.unlock() }
        return (data, response)
    }
}
