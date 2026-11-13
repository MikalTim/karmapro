// by cipher.org.uk
import Foundation

extension PRReviewSession {
    /// Suggested file name for the Markdown report, for example `PR-12-fix-login.md`.
    var reportFileName: String {
        let slug = context.pr.title
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(String(slug).prefix(40))
        return "PR-\(context.pr.number)-\(collapsed.isEmpty ? "review" : collapsed).md"
    }

    /// A/M badge per file name, keyed the way the tree looks nodes up.
    var fileBadges: [String: String] {
        var badges: [String: String] = [:]
        for file in checkout.reviewableFiles {
            badges[URL(fileURLWithPath: file.path).lastPathComponent] = file.kind.badge
        }
        return badges
    }
}
