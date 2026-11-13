// by cipher.org.uk
import AppKit

/// AppKit presentation for scan severities. Kept out of KarmaCore so the
/// scanning engine builds without AppKit (Linux, headless CLI, server).
extension ScanFinding.Severity {
    var color: NSColor {
        switch self {
        case .critical: return NSColor.systemRed
        case .high:     return NSColor.systemOrange
        case .medium:   return NSColor.systemYellow
        case .low:      return NSColor.systemGray
        }
    }
}
