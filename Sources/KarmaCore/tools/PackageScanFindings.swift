import Foundation

/// Rows, ordering and the persisted ignore list of the package (dependency
/// vulnerability) scan. The web front end and the AppKit window share these.
enum PackageScanFindings {
    /// UserDefaults key of the ignored package rows. Unchanged from the AppKit window.
    static let ignoredLinesDefaultsKey = "PackageScanWindowController.ignoredLines"

    /// Turns OSV matches for each resolved dependency into table rows, sorted by
    /// severity (highest first), then package, then vulnerability id.
    static func make(dependencies: [PackageDependency],
                     vulnerabilities: [String: [OSVVulnerability]]) -> [ScanFinding] {
        var out: [ScanFinding] = []
        for dependency in dependencies {
            let key = OSVClient.queryKey(ecosystem: dependency.ecosystem,
                                         name: dependency.name,
                                         version: dependency.version)
            guard let matches = vulnerabilities[key], !matches.isEmpty else { continue }
            for vulnerability in matches {
                let severity: ScanFinding.Severity
                switch OSVClient.severity(of: vulnerability) {
                case .critical: severity = .critical
                case .high: severity = .high
                case .medium: severity = .medium
                case .low: severity = .low
                }
                let summary = vulnerability.summary.flatMap { $0.isEmpty ? nil : $0 }
                    ?? vulnerability.details?.components(separatedBy: "\n").first
                    ?? vulnerability.id
                let displayID = vulnerability.aliases?.first(where: { $0.hasPrefix("CVE-") })
                    ?? vulnerability.id
                out.append(ScanFinding(fileURL: dependency.fileURL,
                                       line: dependency.line,
                                       function: dependency.ecosystem,
                                       category: vulnerability.id,
                                       message: "\(displayID): \(summary)",
                                       taint: nil,
                                       severity: severity,
                                       exploitability: severity,
                                       reachable: true,
                                       taintPath: nil,
                                       ignored: false,
                                       scanningSource: "OSV",
                                       crossFile: false,
                                       packageName: "\(dependency.name)@\(dependency.version)"))
            }
        }
        out.sort { a, b in
            if a.severity != b.severity { return a.severity > b.severity }
            let lhs = a.packageName ?? ""
            let rhs = b.packageName ?? ""
            if lhs != rhs { return lhs < rhs }
            return a.category < b.category
        }
        return out
    }

    /// Compares two rows by one sortable column. `.orderedAscending` means `a`
    /// comes before `b` in the requested direction. Equal values, and unknown
    /// keys (which compare the message), return `.orderedSame` in both directions.
    static func compare(_ a: ScanFinding, _ b: ScanFinding, key: String, ascending: Bool) -> ComparisonResult {
        let result: ComparisonResult
        switch key {
        case "severity":
            result = compareValues(a.severity.rawValue, b.severity.rawValue)
        case "package":
            result = compareValues(a.packageName ?? "", b.packageName ?? "")
        case "fileURL":
            result = compareValues(a.fileURL.lastPathComponent, b.fileURL.lastPathComponent)
        case "line":
            result = compareValues(a.line, b.line)
        default:
            result = compareValues(a.message, b.message)
        }
        if ascending || result == .orderedSame { return result }
        return result == .orderedAscending ? .orderedDescending : .orderedAscending
    }

    /// The persisted key of a package row. It includes the package coordinate,
    /// so it differs from `FindingIgnoreList.key(for:)`, which the code scan uses.
    static func ignoredKey(for finding: ScanFinding) -> String {
        "\(finding.fileURL.path)#\(finding.line)#\(finding.packageName ?? "")"
    }

    /// The stored ignored keys. Reads UserDefaults on every call.
    static func ignoredLines(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: ignoredLinesDefaultsKey) ?? [])
    }

    /// Replaces the stored ignored keys.
    static func setIgnoredLines(_ lines: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(Array(lines), forKey: ignoredLinesDefaultsKey)
    }

    /// Removes the rows whose keys are stored as ignored.
    static func applyIgnored(_ input: [ScanFinding], defaults: UserDefaults = .standard) -> [ScanFinding] {
        let ignored = ignoredLines(defaults: defaults)
        guard !ignored.isEmpty else { return input }
        return input.filter { !ignored.contains(ignoredKey(for: $0)) }
    }

    private static func compareValues<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
        return .orderedSame
    }
}
