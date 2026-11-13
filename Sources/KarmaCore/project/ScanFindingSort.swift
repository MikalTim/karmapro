import Foundation

/// Table ordering and cell text for security-scan findings. Keys are the
/// `NSSortDescriptor` keys the scan table uses, so the web table can use the same ones.
enum ScanFindingSort {
    /// Compares two findings by one sortable column. `.orderedAscending` means
    /// `a` comes before `b` in the requested direction. Equal values, including
    /// unknown keys, return `.orderedSame` in both directions.
    static func compare(_ a: ScanFinding, _ b: ScanFinding, key: String, ascending: Bool) -> ComparisonResult {
        let result: ComparisonResult
        switch key {
        case "line":
            result = compareValues(a.line, b.line)
        case "severity":
            result = compareValues(a.severity.rawValue, b.severity.rawValue)
        case "exploitability":
            result = compareValues(a.exploitability.rawValue, b.exploitability.rawValue)
        case "scanningSource":
            result = compareValues(a.scanningSource, b.scanningSource)
        case "crossFile":
            result = compareValues(a.crossFile ? 1 : 0, b.crossFile ? 1 : 0)
        case "fileURL":
            result = compareValues(a.fileURL.lastPathComponent, b.fileURL.lastPathComponent)
        default:
            // Fall back to a string comparison on whatever text is in that column.
            result = compareValues(displayText(for: key, finding: a), displayText(for: key, finding: b))
        }
        if ascending || result == .orderedSame { return result }
        return result == .orderedAscending ? .orderedDescending : .orderedAscending
    }

    /// The text a sortable column shows for a finding, used for string comparison.
    static func displayText(for key: String, finding f: ScanFinding) -> String {
        switch key {
        case "category": return f.category
        case "function": return f.function
        case "fileURL": return f.fileURL.lastPathComponent
        case "crossFile": return f.crossFile ? "Yes" : "No"
        default: return ""
        }
    }

    /// True when the row names the AI as one of the engines that reported it.
    static func isAIRow(_ f: ScanFinding) -> Bool {
        f.scanningSource.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == "AI" }
    }

    private static func compareValues<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
        return .orderedSame
    }
}
