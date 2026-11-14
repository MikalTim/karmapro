// by cipher.org.uk
import Foundation

/// The Scan Project's Packages window (`PackageScanWindowController`): finds the
/// dependency manifests and lockfiles of the open project and checks every exact
/// package version against a vulnerability API.
///
/// The window's state (detected files, findings, status line, progress, sort order)
/// lives here, guarded by a lock, so every browser tab sees the same scan.
public enum PackageScanService {
    /// The window's description label.
    public static let descriptionText = "Scans this project's dependency manifests and lockfiles for known vulnerabilities by checking every resolved package version against the API source below. Lockfiles are preferred over manifests, and only exact versions are queried."

    /// One entry of the API source popup. `id` is the endpoint URL, sent back as `apiSource` when scanning.
    public struct ApiSourceDTO: Codable, Sendable {
        public var id: String
        /// The popup title, for example "api.osv.dev".
        public var title: String
        public var host: String

        public init(id: String, title: String, host: String) {
            self.id = id
            self.title = title
            self.host = host
        }
    }

    /// One detected dependency manifest or lockfile.
    public struct FileDTO: Codable, Sendable {
        /// Absolute path.
        public var path: String
        public var relativePath: String
        public var language: String
        public var ecosystem: String
        public var isLockfile: Bool
        /// "lockfile" or "manifest".
        public var kind: String
        /// The line the window's file list shows for the file.
        public var label: String

        public init(path: String, relativePath: String, language: String, ecosystem: String,
                    isLockfile: Bool, kind: String, label: String) {
            self.path = path
            self.relativePath = relativePath
            self.language = language
            self.ecosystem = ecosystem
            self.isLockfile = isLockfile
            self.kind = kind
            self.label = label
        }
    }

    /// One row of the findings table. Rows the user ignored are not listed.
    public struct FindingDTO: Codable, Sendable {
        /// The persisted ignore key of the row; send it to `setIgnored(key:ignored:)` to hide the row.
        public var key: String
        /// Absolute path of the manifest or lockfile the package comes from.
        public var path: String
        /// The file name shown in the File column.
        public var file: String
        /// "name@version" of the package, shown in the Package column.
        public var package: String
        /// "critical", "high", "medium" or "low".
        public var severity: String
        /// "Critical", "High", "Medium" or "Low".
        public var severityLabel: String
        public var line: Int
        /// The Finding column text (the advisory id and summary).
        public var message: String

        public init(key: String, path: String, file: String, package: String, severity: String,
                    severityLabel: String, line: Int, message: String) {
            self.key = key
            self.path = path
            self.file = file
            self.package = package
            self.severity = severity
            self.severityLabel = severityLabel
            self.line = line
            self.message = message
        }
    }

    /// Everything the window shows.
    public struct StateDTO: Codable, Sendable {
        public var descriptionText: String
        public var apiSources: [ApiSourceDTO]
        /// The `id` of the source the popup selects.
        public var selectedApiSource: String
        /// The privacy line under the popup, naming the selected source's host.
        public var privacyNote: String
        public var files: [FileDTO]
        public var findings: [FindingDTO]
        public var statusText: String
        /// "secondary", "warning" or "error": the colour of the status line.
        public var statusTone: String
        /// True while a detection or scan runs.
        public var busy: Bool
        /// Scan progress from 0 to 1, or nil when the bar is not determinate (indeterminate or hidden).
        public var progress: Double?
        /// The Scan button is enabled: idle, and files were detected.
        public var scanEnabled: Bool
        /// The Export button is enabled: at least one finding is listed.
        public var exportEnabled: Bool
        /// The column the table is sorted by, or nil for the default order.
        public var sortKey: String?
        public var sortAscending: Bool

        public init(descriptionText: String, apiSources: [ApiSourceDTO], selectedApiSource: String,
                    privacyNote: String, files: [FileDTO], findings: [FindingDTO], statusText: String,
                    statusTone: String, busy: Bool, progress: Double?, scanEnabled: Bool,
                    exportEnabled: Bool, sortKey: String?, sortAscending: Bool) {
            self.descriptionText = descriptionText
            self.apiSources = apiSources
            self.selectedApiSource = selectedApiSource
            self.privacyNote = privacyNote
            self.files = files
            self.findings = findings
            self.statusText = statusText
            self.statusTone = statusTone
            self.busy = busy
            self.progress = progress
            self.scanEnabled = scanEnabled
            self.exportEnabled = exportEnabled
            self.sortKey = sortKey
            self.sortAscending = sortAscending
        }
    }

    /// The API source popup's items (the window offers only the OSV endpoint).
    static let apiSourceChoices: [(url: URL, title: String)] = [
        (OSVClient.defaultEndpoint, "api.osv.dev"),
    ]

    // MARK: - Public API

    /// `POST /api/packages/detect`: re-detects the package files of the open project and returns the job id.
    public static func detect() throws -> String {
        let root = try projectRoot()
        try store.begin()
        return KarmaJobCenter.shared.start(kind: "packages-detect") { _ in
            _ = runDetection(root: root)
            return KarmaJSON.data(snapshot())
        }
    }

    /// `POST /api/packages/scan`: detects the package files again and queries `apiSource`
    /// (nil selects the popup's default). Returns the job id; its result is the new `StateDTO`.
    public static func scan(apiSource: String?) throws -> String {
        let root = try projectRoot()
        let endpoint = try endpoint(for: apiSource)
        try store.begin()
        return KarmaJobCenter.shared.start(kind: "packages-scan") { context in
            let host = endpoint.host ?? "the selected service"
            let detection = PackageDetector.detect(root: root)
            var outcome: [ScanFinding] = []
            var failure: String?
            if !detection.dependencies.isEmpty {
                do {
                    let vulnerabilities = try OSVClient.vulnerabilities(for: detection.dependencies,
                                                                        endpoint: endpoint) { stage in
                        let report = progressReport(stage, host: host)
                        store.setStatus(report.text, fraction: report.fraction)
                        context.progress(done: report.done, total: report.total, stage: report.text)
                    }
                    outcome = PackageScanFindings.make(dependencies: detection.dependencies,
                                                       vulnerabilities: vulnerabilities)
                } catch {
                    failure = error.localizedDescription
                }
            }
            store.finishScan(detection: detection, outcome: outcome, failure: failure, defaults: .standard)
            return KarmaJSON.data(snapshot())
        }
    }

    /// `GET /api/packages`: the current state of the window.
    public static func state() -> StateDTO {
        snapshot()
    }

    /// `POST /api/packages/ignore`: hides (or shows again) the row with `key`, and returns the new state.
    public static func setIgnored(key: String, ignored: Bool) -> StateDTO {
        setIgnored(key: key, ignored: ignored, defaults: .standard)
        return snapshot()
    }

    /// Sorts the table by `key` ("severity", "package", "fileURL", "line" or "msg"), or restores the default order when nil.
    public static func sort(key: String?, ascending: Bool) -> StateDTO {
        store.setSort(key: key, ascending: ascending)
        return snapshot()
    }

    /// `GET /api/packages/export`: the SARIF file for the rows shown in the table, named as the save panel names it.
    public static func export() throws -> (fileName: String, data: Data) {
        let rows = visibleFindings(defaults: .standard)
        guard !rows.isEmpty else {
            throw KarmaServiceError.invalid("There are no findings to export.")
        }
        return ("KarmaPro-packages.sarif.json", try SARIFExport.data(from: rows))
    }

    // MARK: - Internals

    private static let store = Store()

    /// The open project, or the window's "No Project Folder Open" message.
    private static func projectRoot() throws -> URL {
        guard let root = KarmaWorkspace.shared.read({ $0.root }) else {
            throw KarmaServiceError.invalid("No Project Folder Open. Open a project folder first so its dependency manifests and lockfiles can be detected, then run the package scan again.")
        }
        return root
    }

    /// The endpoint for a source identifier from the popup, or the popup's default when nil.
    private static func endpoint(for apiSource: String?) throws -> URL {
        guard let apiSource else { return apiSourceChoices[0].url }
        guard let choice = apiSourceChoices.first(where: { $0.url.absoluteString == apiSource }) else {
            throw KarmaServiceError.invalid("Unknown vulnerability API source \"\(apiSource)\".")
        }
        return choice.url
    }

    /// Detects the package files of `root` and records them as the window does after a detection.
    static func runDetection(root: URL) -> StateDTO {
        store.applyDetection(PackageDetector.detect(root: root))
        return snapshot()
    }

    /// Stores the ignore key in the same `UserDefaults` list the window uses.
    static func setIgnored(key: String, ignored: Bool, defaults: UserDefaults) {
        var lines = PackageScanFindings.ignoredLines(defaults: defaults)
        if ignored {
            lines.insert(key)
        } else {
            lines.remove(key)
        }
        PackageScanFindings.setIgnoredLines(lines, defaults: defaults)
    }

    /// The rows the table shows: the findings minus the ignored ones, in the current sort order.
    static func visibleFindings(defaults: UserDefaults) -> [ScanFinding] {
        let (findings, key, ascending) = store.findingsAndSort()
        return sorted(PackageScanFindings.applyIgnored(findings, defaults: defaults), key: key, ascending: ascending)
    }

    /// The window's `applySorting`: orders `input` by `key` in the requested direction.
    static func sorted(_ input: [ScanFinding], key: String?, ascending: Bool) -> [ScanFinding] {
        guard let key else { return input }
        return input.sorted { a, b in
            PackageScanFindings.compare(a, b, key: key, ascending: ascending) == .orderedAscending
        }
    }

    /// The status line, progress and the text of a progress callback (`scanClicked`).
    static func progressReport(_ stage: OSVClient.Progress, host: String) -> (text: String, fraction: Double?, done: Int, total: Int) {
        switch stage {
        case .querying(let done, let total):
            let fraction = total > 0 ? 0.7 * Double(done) / Double(total) : nil
            return ("Querying \(host)… \(done)/\(total) packages", fraction, done, total)
        case .fetchingDetails(let done, let total):
            let fraction = total > 0 ? 0.7 + 0.3 * Double(done) / Double(total) : nil
            return ("Fetching vulnerability details… \(done)/\(total)", fraction, done, total)
        }
    }

    static func snapshot(defaults: UserDefaults = .standard) -> StateDTO {
        let view = store.view()
        let rows = sorted(PackageScanFindings.applyIgnored(view.findings, defaults: defaults),
                          key: view.sortKey, ascending: view.sortAscending)
        let choices = apiSourceChoices.map { choice in
            ApiSourceDTO(id: choice.url.absoluteString, title: choice.title, host: choice.url.host ?? "")
        }
        let selected = choices[0]
        return StateDTO(
            descriptionText: descriptionText,
            apiSources: choices,
            selectedApiSource: selected.id,
            privacyNote: "Privacy: package names and versions are sent to \(selected.host) when you scan. Source code, file contents, and file paths are never sent.",
            files: view.files.map(fileDTO),
            findings: rows.map(findingDTO),
            statusText: view.statusText,
            statusTone: view.statusTone,
            busy: view.busy,
            progress: view.progress,
            scanEnabled: !view.busy && !view.files.isEmpty,
            exportEnabled: !rows.isEmpty,
            sortKey: view.sortKey,
            sortAscending: view.sortAscending)
    }

    private static func fileDTO(_ file: PackageDetection.DetectedFile) -> FileDTO {
        let kind = file.isLockfile ? "lockfile" : "manifest"
        return FileDTO(path: file.url.path,
                       relativePath: file.relativePath,
                       language: file.language,
                       ecosystem: file.ecosystem,
                       isLockfile: file.isLockfile,
                       kind: kind,
                       label: "\(file.relativePath) — \(file.language)/\(file.ecosystem) (\(kind))")
    }

    private static func findingDTO(_ finding: ScanFinding) -> FindingDTO {
        FindingDTO(key: PackageScanFindings.ignoredKey(for: finding),
                   path: finding.fileURL.path,
                   file: finding.fileURL.lastPathComponent,
                   package: finding.packageName ?? "",
                   severity: rawSeverity(finding.severity),
                   severityLabel: finding.severity.label,
                   line: finding.line,
                   message: finding.message)
    }

    private static func rawSeverity(_ severity: ScanFinding.Severity) -> String {
        switch severity {
        case .critical: return "critical"
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        }
    }

    /// The window's state. Every field is read and written under `lock`.
    private final class Store {
        struct View {
            var files: [PackageDetection.DetectedFile]
            var findings: [ScanFinding]
            var statusText: String
            var statusTone: String
            var busy: Bool
            var progress: Double?
            var sortKey: String?
            var sortAscending: Bool
        }

        private let lock = NSLock()
        private var files: [PackageDetection.DetectedFile] = []
        /// Every finding of the last completed scan, before the ignore list is applied.
        private var findings: [ScanFinding] = []
        private var statusText = "Detecting package files…"
        private var statusTone = "secondary"
        private var busy = false
        private var progress: Double?
        private var sortKey: String?
        private var sortAscending = true

        /// Marks a detection or scan as running. Fails when one already runs.
        func begin() throws {
            lock.lock()
            defer { lock.unlock() }
            guard !busy else {
                throw KarmaServiceError.busy("A package scan is already running. Wait for it to finish.")
            }
            busy = true
            statusText = "Detecting package files…"
            statusTone = "secondary"
            progress = nil
        }

        func view() -> View {
            lock.lock()
            defer { lock.unlock() }
            return View(files: files, findings: findings, statusText: statusText, statusTone: statusTone,
                        busy: busy, progress: progress, sortKey: sortKey, sortAscending: sortAscending)
        }

        func findingsAndSort() -> ([ScanFinding], String?, Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (findings, sortKey, sortAscending)
        }

        func setSort(key: String?, ascending: Bool) {
            lock.lock()
            defer { lock.unlock() }
            sortKey = key
            sortAscending = ascending
        }

        func setStatus(_ text: String, fraction: Double?) {
            lock.lock()
            defer { lock.unlock() }
            statusText = text
            if let fraction { progress = fraction }
        }

        /// The window's `performDetection` completion: records the files and the status line. Detection runs when
        /// the window opens, and a new AppKit window starts without findings or a sort, so those reset here.
        func applyDetection(_ detection: PackageDetection) {
            lock.lock()
            defer { lock.unlock() }
            busy = false
            progress = nil
            findings = []
            sortKey = nil
            sortAscending = true
            applyFiles(detection.files, entries: detection.dependencies.count)
        }

        /// The window's `finishScan`: records the outcome of a scan and its status line.
        func finishScan(detection: PackageDetection, outcome: [ScanFinding], failure: String?, defaults: UserDefaults) {
            lock.lock()
            defer { lock.unlock() }
            busy = false
            progress = nil
            if let failure {
                statusTone = "error"
                statusText = "Scan failed: \(failure)"
                return
            }
            guard !detection.files.isEmpty else {
                applyFiles([], entries: 0)
                findings = []
                return
            }
            files = detection.files
            findings = outcome
            statusTone = "secondary"
            guard !outcome.isEmpty else {
                statusText = "Scan complete: no known vulnerabilities found."
                return
            }
            let total = outcome.count
            var text = "Scan complete: \(total) known vulnerabilit\(total == 1 ? "y" : "ies") found."
            let hidden = total - PackageScanFindings.applyIgnored(outcome, defaults: defaults).count
            if hidden > 0 {
                text += " (\(hidden) ignored row\(hidden == 1 ? "" : "s") hidden)"
            }
            statusText = text
        }

        /// Lock must be held.
        private func applyFiles(_ detected: [PackageDetection.DetectedFile], entries: Int) {
            files = detected
            if detected.isEmpty {
                statusText = "The current project is not supported for package scanning"
                statusTone = "warning"
            } else {
                statusText = "\(entries) package entr\(entries == 1 ? "y" : "ies") in \(detected.count) file\(detected.count == 1 ? "" : "s"). Click Scan to query."
                statusTone = "secondary"
            }
        }
    }
}
