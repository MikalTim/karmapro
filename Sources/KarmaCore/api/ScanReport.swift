// by cipher.org.uk
import Foundation

// Public, front-end-neutral entry point to the scanning engine.
//
// Everything else in KarmaCore stays internal. Front ends that live outside
// this module (the headless `karma` CLI, a future Vapor server) talk to the
// engine only through `KarmaScanner` and the Codable `ScanReport` it returns,
// so they can serialize results without knowing the engine's internal types.

/// Runs the built-in static scan (AST + heuristic engines) over a project.
public enum KarmaScanner {
    /// Scans every supported source file under `root`.
    ///
    /// - Parameters:
    ///   - progress: called once per file with `(filesDone, filesTotal)`.
    ///   - isCancelled: polled between files; when it returns true the scan
    ///     stops and the report is marked `cancelled` with the partial results.
    public static func scan(root: URL,
                            progress: ((Int, Int) -> Void)? = nil,
                            isCancelled: (() -> Bool)? = nil) -> ScanReport {
        let root = root.standardizedFileURL
        let started = Date()
        var filesTotal = 0
        var cancelled = false
        let findings = VulnerabilityScanner.scan(
            projectRoot: root,
            progress: { done, total in
                filesTotal = total
                progress?(done, total)
            },
            isCancelled: {
                guard let isCancelled, isCancelled() else { return false }
                cancelled = true
                return true
            })
        let finished = Date()
        // The engine orders by severity only; ties follow directory enumeration
        // order, which differs between file systems. Break ties by location so
        // the same project always yields the same, diffable report.
        let reported = findings.map { ScanReport.Finding($0, root: root) }.sorted {
            if $0.severity != $1.severity { return $0.severity.rank > $1.severity.rank }
            if $0.file != $1.file { return $0.file < $1.file }
            if $0.line != $1.line { return $0.line < $1.line }
            return $0.category < $1.category
        }
        return ScanReport(
            root: root.path,
            startedAt: started,
            durationSeconds: finished.timeIntervalSince(started),
            cancelled: cancelled,
            filesScanned: filesTotal,
            summary: ScanReport.Summary(reported),
            findings: reported)
    }
}

/// The result of one static scan, ready to encode as JSON.
public struct ScanReport: Codable, Equatable, Sendable {
    public enum Severity: String, Codable, Equatable, Sendable, CaseIterable {
        case critical, high, medium, low
    }

    public struct Finding: Codable, Equatable, Sendable {
        /// Path relative to the scanned root (absolute when outside it).
        public var file: String
        /// 1-based line of the sink.
        public var line: Int
        /// Enclosing function, or the file name for file-level findings.
        public var function: String
        public var category: String
        public var message: String
        public var severity: Severity
        /// Evidence-based likelihood of being exploitable.
        public var exploitability: Severity
        /// Whether the enclosing function is reachable at runtime.
        public var reachable: Bool
        /// Detecting engine: "AST" or "Heuristic".
        public var engine: String
        /// True when the tainted data originates in another file.
        public var crossFile: Bool
        /// Short description of the data-flow path, if any.
        public var taint: String?
        /// Source-to-sink variable trace, if any.
        public var taintPath: String?
        /// "name@version" for package findings.
        public var package: String?
    }

    public struct Summary: Codable, Equatable, Sendable {
        public var total: Int
        public var bySeverity: [String: Int]
        public var byEngine: [String: Int]
        public var byCategory: [String: Int]

        init(_ findings: [Finding]) {
            total = findings.count
            bySeverity = Dictionary(uniqueKeysWithValues: Severity.allCases.map { ($0.rawValue, 0) })
            byEngine = [:]
            byCategory = [:]
            for f in findings {
                bySeverity[f.severity.rawValue, default: 0] += 1
                byEngine[f.engine, default: 0] += 1
                byCategory[f.category, default: 0] += 1
            }
        }
    }

    public var root: String
    public var startedAt: Date
    public var durationSeconds: Double
    public var cancelled: Bool
    public var filesScanned: Int
    public var summary: Summary
    /// Most severe first, then by file, line and category.
    public var findings: [Finding]

    /// Stable, human-readable JSON (sorted keys, ISO-8601 dates).
    public func jsonData(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                                          : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Keeps findings at or above `minimum`, recomputing the summary.
    public func filtered(minimumSeverity minimum: Severity) -> ScanReport {
        var copy = self
        copy.findings = findings.filter { $0.severity.rank >= minimum.rank }
        copy.summary = Summary(copy.findings)
        return copy
    }
}

extension ScanReport.Severity {
    init(_ severity: ScanFinding.Severity) {
        switch severity {
        case .critical: self = .critical
        case .high:     self = .high
        case .medium:   self = .medium
        case .low:      self = .low
        }
    }

    /// Ordering shared with the engine: critical 3 … low 0.
    var rank: Int {
        switch self {
        case .critical: return ScanFinding.Severity.critical.rawValue
        case .high:     return ScanFinding.Severity.high.rawValue
        case .medium:   return ScanFinding.Severity.medium.rawValue
        case .low:      return ScanFinding.Severity.low.rawValue
        }
    }
}

extension ScanReport.Finding {
    init(_ finding: ScanFinding, root: URL) {
        let path = finding.fileURL.standardizedFileURL.path
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        file = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        line = finding.line
        function = finding.function
        category = finding.category
        message = finding.message
        severity = ScanReport.Severity(finding.severity)
        exploitability = ScanReport.Severity(finding.exploitability)
        reachable = finding.reachable
        engine = finding.scanningSource
        crossFile = finding.crossFile
        taint = finding.taint
        taintPath = finding.taintPath
        package = finding.packageName
    }
}
