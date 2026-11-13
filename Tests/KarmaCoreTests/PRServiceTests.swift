import Foundation
import XCTest
@testable import KarmaCore

/// The pull request service: alert batching, the changes window's lines and the review's effect on the project.
final class PRServiceTests: XCTestCase {

    private func makeRepo() -> MonitoredRepo {
        MonitoredRepo(provider: "github", baseURL: "https://api.github.com", webURL: "https://github.com",
                      repoSlug: "owner/name")
    }

    private func makePR(id: Int, title: String = "Title", author: String = "me", updated: TimeInterval? = nil) -> PullRequest {
        PullRequest(id: id, number: id, title: title, author: author, headBranch: "feature", baseBranch: "main",
                    repoSlug: "owner/name", webURL: "https://github.com/owner/name/pull/\(id)",
                    headSHA: "abcdef123456", updatedAt: updated.map { Date(timeIntervalSince1970: $0) })
    }

    func testAlertsAreCappedAtFiveNewestFirstAndSayHowManyArrived() {
        let repo = makeRepo()
        let fresh = (1...7).map { PRActionItem(repo: repo, pr: makePR(id: $0, updated: Double($0)), isNew: true) }

        let alerts = PRService.notifications(for: fresh)

        XCTAssertEqual(alerts.map(\.prID), [7, 6, 5, 4, 3])
        XCTAssertEqual(alerts[0].title, "owner/name #7")
        XCTAssertEqual(alerts[0].body,
                       "#7 Title \u{2014} me\n7 new since you last looked \u{2014} 5 most recent shown, the rest are in the watch list.")
    }

    func testAlertForASinglePullRequestIsJustItsHeadline() {
        let item = PRActionItem(repo: makeRepo(), pr: makePR(id: 3, title: "Fix login", author: "ann"), isNew: true)

        XCTAssertEqual(PRService.notifications(for: [item]).map(\.body), ["#3 Fix login \u{2014} ann"])
        XCTAssertTrue(PRService.notifications(for: []).isEmpty)
    }

    func testDiffLinesAreClassifiedAndOnlyRiskyAdditionsAreFlagged() {
        let patch = "@@ -1,2 +1,3 @@\n context\n-old line\n+os.system(cmd)\n+plain line\nindex 12ab..34cd\nBinary files differ"

        let lines = PRService.lines(of: patch)

        XCTAssertEqual(lines.map(\.kind), ["hunk", "context", "removed", "added", "added", "meta", "meta"])
        XCTAssertEqual(lines.map(\.suspicious), [false, false, false, true, false, false, false])
    }

    func testReviewPrunesTheTreeToTheChangedFilesAndClosingItEmptiesTheWindow() throws {
        let workspaceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-pr-\(UUID().uuidString)", isDirectory: true)
        for (path, text) in ["src/a.c": "int a;\n", "src/b.c": "int b;\n", "README.md": "# readme\n"] {
            let url = workspaceRoot.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: workspaceRoot) }

        let changed = ChangedFile(path: "src/a.c", oldPath: nil, kind: .modified,
                                  hunks: [DiffHunk(headStart: 1, headEnd: 2, baseStart: 1, baseEnd: 2)],
                                  patch: "@@ -1 +1 @@\n-int x;\n+int a;")
        let removed = ChangedFile(path: "src/gone.c", oldPath: nil, kind: .deleted, hunks: [], patch: "")
        let checkout = PreparedCheckout(workspace: workspaceRoot, changedFiles: [changed, removed],
                                        baseRef: "origin/main", headRef: "feature", sourceClone: nil)
        let session = PRReviewSession(repo: makeRepo(), pr: makePR(id: 9, title: "Fix a"), checkout: checkout)
        let service = PRService.shared

        try service.openReview(session)

        XCTAssertTrue(service.hasActiveReview)
        let banner = try XCTUnwrap(service.state().review)
        XCTAssertEqual(banner.title, "PR #9 Fix a")
        XCTAssertEqual(banner.subtitle, "Reviewing PR #9 · owner/name · 1 files")
        XCTAssertTrue(banner.showAllAvailable)
        let pruned = try XCTUnwrap(ProjectService.tree(language: nil, query: nil).root)
        XCTAssertEqual(pruned.children?.map(\.name), ["src"])
        XCTAssertEqual(pruned.children?.first?.children?.map(\.name), ["a.c"])
        XCTAssertEqual(pruned.children?.first?.children?.first?.badge, "M")

        let changes = try service.changes()
        XCTAssertEqual(changes.files.map(\.title), ["M  src/a.c"])
        XCTAssertEqual(changes.files.first?.absolutePath, workspaceRoot.appendingPathComponent("src/a.c").path)
        XCTAssertEqual(try service.report().suggestedName, "PR-9-fix-a.md")

        try service.showAllFiles()
        XCTAssertEqual(service.state().review?.showAllAvailable, false)
        let everything = try XCTUnwrap(ProjectService.tree(language: nil, query: nil).root)
        XCTAssertEqual(Set(everything.children?.map(\.name) ?? []), ["README.md", "src"])

        service.leaveReview()

        XCTAssertFalse(service.hasActiveReview)
        XCTAssertNil(service.state().review)
        XCTAssertNil(try ProjectService.tree(language: nil, query: nil).root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspaceRoot.path), "closing the review removes its checkout")
        XCTAssertThrowsError(try service.changes())
    }
}
