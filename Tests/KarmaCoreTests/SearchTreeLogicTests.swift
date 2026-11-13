import Foundation
import XCTest
@testable import KarmaCore

final class SearchTreeLogicTests: XCTestCase {

    // MARK: - ProjectTextSearch

    private func describe(_ matches: [ProjectTextMatch]) -> [String] {
        matches.map { "\($0.fileURL.lastPathComponent):\($0.line):\($0.text)" }.sorted()
    }

    private func makeSearchProject() throws -> ScanFixture {
        try ScanFixture([
            "src/main.swift": "let Foo = 1\nprint(foo)\n",
            "docs/notes.txt": "nothing here\nFOO bar\n",
            "image.png": "foo",
            ".hidden/secret.txt": "foo"
        ])
    }

    func testSearchIsCaseInsensitiveAndNumbersLinesFromOne() throws {
        let project = try makeSearchProject()
        let matches = ProjectTextSearch.search(term: "foo", root: project.root, language: nil, isCancelled: { false })
        XCTAssertEqual(describe(matches), [
            "main.swift:1:let Foo = 1",
            "main.swift:2:print(foo)",
            "notes.txt:2:FOO bar"
        ])
    }

    func testUpperCaseTermMatchesTheSameLines() throws {
        let project = try makeSearchProject()
        let lower = ProjectTextSearch.search(term: "foo", root: project.root, language: nil, isCancelled: { false })
        let upper = ProjectTextSearch.search(term: "FOO", root: project.root, language: nil, isCancelled: { false })
        XCTAssertEqual(describe(upper), describe(lower))
    }

    func testSkipsHiddenFilesAndBinaryExtensions() throws {
        let project = try makeSearchProject()
        let matches = ProjectTextSearch.search(term: "secret", root: project.root, language: nil, isCancelled: { false })
        XCTAssertTrue(matches.isEmpty, "hidden directory contents must not be searched")
        let images = ProjectTextSearch.search(term: "foo", root: project.root, language: nil, isCancelled: { false })
        XCTAssertFalse(images.contains { $0.fileURL.lastPathComponent == "image.png" },
                       "files with an image extension are skipped")
    }

    func testLanguageFilterRestrictsSearchToThatLanguage() throws {
        let project = try makeSearchProject()
        let swift = Language(name: "Swift", extensions: ["swift"])
        let matches = ProjectTextSearch.search(term: "foo", root: project.root, language: swift, isCancelled: { false })
        XCTAssertEqual(describe(matches), [
            "main.swift:1:let Foo = 1",
            "main.swift:2:print(foo)"
        ])
    }

    func testEmptyTermReturnsNothing() throws {
        let project = try makeSearchProject()
        XCTAssertTrue(ProjectTextSearch.search(term: "", root: project.root, language: nil, isCancelled: { false }).isEmpty)
    }

    func testCancelledSearchStopsBeforeReadingFiles() throws {
        let project = try makeSearchProject()
        let matches = ProjectTextSearch.search(term: "foo", root: project.root, language: nil, isCancelled: { true })
        XCTAssertTrue(matches.isEmpty)
    }

    // MARK: - FileNode filtering

    /// Builds a tree without touching the disk:
    /// /proj/src/{util/Helper.swift, app.swift}, /proj/README.md, /proj/docs/guide.md
    private struct SampleTree {
        let root: FileNode
        let src: FileNode
        let util: FileNode
        let app: FileNode
        let helper: FileNode
        let readme: FileNode
        let docs: FileNode
        let guide: FileNode

        init() {
            func node(_ path: String, dir: Bool) -> FileNode {
                FileNode(url: URL(fileURLWithPath: "/proj/" + path), isDirectory: dir)
            }
            root = node("", dir: true)
            src = node("src", dir: true)
            util = node("src/util", dir: true)
            app = node("src/app.swift", dir: false)
            helper = node("src/util/Helper.swift", dir: false)
            readme = node("README.md", dir: false)
            docs = node("docs", dir: true)
            guide = node("docs/guide.md", dir: false)
            root.children = [src, readme, docs]
            src.children = [util, app]
            util.children = [helper]
            docs.children = [guide]
        }
    }

    func testFilteredByLanguageKeepsOnlyMatchingFilesAndTheirDirectories() {
        let tree = SampleTree()
        let swift = Language(name: "Swift", extensions: ["swift"])
        let result = tree.root.filtered(language: swift)

        XCTAssertEqual(result.children.map(\.name), ["src"], "README.md and docs/ hold no Swift files")
        let src = result.children[0]
        XCTAssertFalse(src === tree.src, "directories are copies, not the original nodes")
        XCTAssertEqual(src.children.map(\.name), ["util", "app.swift"])
        XCTAssertTrue(src.children[1] === tree.app, "matching files are the original instances")
        XCTAssertEqual(src.children[0].children.map(\.name), ["Helper.swift"])
        XCTAssertTrue(src.children[0].children[0] === tree.helper)
    }

    func testFilteredByLanguageWithNoMatchesLeavesAnEmptyRoot() {
        let tree = SampleTree()
        let rust = Language(name: "Rust", extensions: ["rs"])
        let result = tree.root.filtered(language: rust)
        XCTAssertTrue(result.isDirectory)
        XCTAssertTrue(result.children.isEmpty)
    }

    func testFilteredSingleFileReturnsSelfWhenKept() {
        let tree = SampleTree()
        let swift = Language(name: "Swift", extensions: ["swift"])
        XCTAssertTrue(tree.app.filtered(language: swift) === tree.app)
        let other = tree.readme.filtered(language: swift)
        XCTAssertFalse(other === tree.readme)
        XCTAssertEqual(other.name, "README.md")
        XCTAssertTrue(other.children.isEmpty)
    }

    func testFilteredByPredicateKeepsOnlyAcceptedFiles() {
        let tree = SampleTree()
        let result = tree.root.filtered { $0.name == "README.md" }
        XCTAssertEqual(result.children.map(\.name), ["README.md"])
        XCTAssertTrue(result.children[0] === tree.readme)
    }

    func testMatchingFilesIsDepthFirstAndExcludesTheNodeItself() {
        let tree = SampleTree()
        XCTAssertEqual(tree.root.matchingFiles(query: "swift").map(\.name), ["Helper.swift", "app.swift"])
        XCTAssertEqual(tree.root.matchingFiles(query: "guide").map(\.name), ["guide.md"])
        XCTAssertEqual(tree.root.matchingFiles(query: "src").map(\.name), ["src"])
        XCTAssertTrue(tree.root.matchingFiles(query: "proj").isEmpty, "the root itself is never a match")
    }

    func testMatchesPullRequestUsesRepositoryRelativePaths() {
        let tree = SampleTree()
        let root = URL(fileURLWithPath: "/proj")
        let paths: Set<String> = ["src/app.swift"]

        XCTAssertTrue(FileNode.matchesPullRequest(tree.app, paths: paths, root: root))
        XCTAssertFalse(FileNode.matchesPullRequest(tree.helper, paths: paths, root: root))
        XCTAssertFalse(FileNode.matchesPullRequest(tree.readme, paths: paths, root: root))
        XCTAssertTrue(FileNode.matchesPullRequest(tree.src, paths: paths, root: root),
                      "a directory is kept when a changed path sits beneath it")
        XCTAssertFalse(FileNode.matchesPullRequest(tree.util, paths: paths, root: root))
        XCTAssertTrue(FileNode.matchesPullRequest(tree.root, paths: paths, root: root))
    }

    func testPullRequestPredicateProducesPrunedTree() {
        let tree = SampleTree()
        let root = URL(fileURLWithPath: "/proj")
        let paths: Set<String> = ["src/app.swift"]
        let result = tree.root.filtered { FileNode.matchesPullRequest($0, paths: paths, root: root) }
        XCTAssertEqual(result.children.map(\.name), ["src"])
        XCTAssertEqual(result.children[0].children.map(\.name), ["app.swift"])
    }

    // MARK: - PRReviewSession presentation

    private func makeSession(number: Int = 7, title: String, files: [ChangedFile] = []) -> PRReviewSession {
        let repo = MonitoredRepo(provider: "github",
                                 baseURL: "https://api.github.com",
                                 webURL: "https://github.com",
                                 repoSlug: "owner/name")
        let pr = PullRequest(id: 1,
                             number: number,
                             title: title,
                             author: "me",
                             headBranch: "feature",
                             baseBranch: "main",
                             repoSlug: "owner/name",
                             webURL: "https://github.com/owner/name/pull/\(number)",
                             headSHA: "abcdef123456",
                             updatedAt: nil)
        let checkout = PreparedCheckout(workspace: URL(fileURLWithPath: "/tmp/ws"),
                                        changedFiles: files,
                                        baseRef: "origin/main",
                                        headRef: "feature",
                                        sourceClone: nil)
        return PRReviewSession(repo: repo, pr: pr, checkout: checkout)
    }

    func testReportFileNameSlugsTheTitle() {
        XCTAssertEqual(makeSession(title: "Fix: login/flow 2!").reportFileName, "PR-7-fix--login-flow-2-.md")
    }

    func testReportFileNameFallsBackToReviewForEmptySlug() {
        XCTAssertEqual(makeSession(title: "").reportFileName, "PR-7-review.md")
    }

    func testReportFileNameTruncatesSlugToFortyCharacters() {
        let title = String(repeating: "a", count: 50)
        XCTAssertEqual(makeSession(title: title).reportFileName,
                       "PR-7-\(String(repeating: "a", count: 40)).md")
    }

    func testFileBadgesUseReviewableFilesOnly() {
        let files = [
            ChangedFile(path: "src/new.swift", oldPath: nil, kind: .added, hunks: [], patch: ""),
            ChangedFile(path: "lib/Old.java", oldPath: nil, kind: .modified, hunks: [], patch: ""),
            ChangedFile(path: "gone.c", oldPath: nil, kind: .deleted, hunks: [], patch: ""),
            ChangedFile(path: "a/x.h", oldPath: nil, kind: .added, hunks: [], patch: ""),
            ChangedFile(path: "b/x.h", oldPath: nil, kind: .modified, hunks: [], patch: "")
        ]
        let badges = makeSession(title: "t", files: files).fileBadges
        XCTAssertEqual(badges, ["new.swift": "A", "Old.java": "M", "x.h": "M"],
                       "deleted files are not reviewable; the later file with the same name wins")
    }
}
