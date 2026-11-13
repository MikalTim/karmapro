import XCTest
@testable import KarmaCore

final class HelpAndDiffTests: XCTestCase {

    // MARK: HelpMarkdown

    func testHeadingsListsAndBoldRenderInOrder() {
        let markdown = """
        # Title
        ## Section
        - item **bold** here
        Plain **b** text & <x>
        """
        let page = HelpMarkdown.page(markdown: markdown, splashImageSrc: nil)

        let body = """
        <h1>Title</h1>
        <h2>Section</h2>
        <ul><li>item <strong>bold</strong> here</li>
        </ul><p>Plain <strong>b</strong> text &amp; &lt;x&gt;</p>

        """
        XCTAssertTrue(page.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(page.contains("<body>\n" + body + "\n</body>"))
    }

    func testNumberedLinesBecomeBoldParagraphs() {
        let page = HelpMarkdown.page(markdown: "1. Open a folder\n", splashImageSrc: nil)
        XCTAssertTrue(page.contains("<body>\n<p><strong>1. Open a folder</strong></p>\n<br/>\n\n</body>"))
    }

    func testSplashLineUsesGivenSource() {
        let markdown = "# T\n![Karma Pro Splash](HelpSplash.jpg)\nText"
        let page = HelpMarkdown.page(markdown: markdown, splashImageSrc: "/api/resources/HelpSplash.jpg")

        XCTAssertTrue(page.contains("<h1>T</h1>\n<div style='text-align:center; margin: 20px 0;'><img src='/api/resources/HelpSplash.jpg' style='max-width:320px; border-radius:8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);'/></div>\n<p>Text</p>\n"))
    }

    func testSplashLineProducesNothingWithoutSource() {
        let markdown = "# T\n![Karma Pro Splash](HelpSplash.jpg)\nText"
        let page = HelpMarkdown.page(markdown: markdown, splashImageSrc: nil)

        XCTAssertTrue(page.contains("<body>\n<h1>T</h1>\n<p>Text</p>\n\n</body>"))
        XCTAssertFalse(page.contains("<img"))
    }

    func testBackticksPassThroughUnconverted() {
        // The converter has no inline-code rule; `code` only styles <code> tags, which
        // the escaping step never produces. Backticks therefore stay literal.
        let page = HelpMarkdown.page(markdown: "Use `ls -la` now", splashImageSrc: nil)
        XCTAssertTrue(page.contains("<p>Use `ls -la` now</p>\n"))
        XCTAssertTrue(page.contains("code { background: #eee;"))
    }

    // MARK: PRDiffSummary

    private func changedFile(oldPath: String?, patch: String) -> ChangedFile {
        ChangedFile(path: "a.swift", oldPath: oldPath, kind: .modified, hunks: [], patch: patch)
    }

    func testSummaryCountsAddedAndRemovedAndFlagsSuspiciousLines() {
        let file = changedFile(
            oldPath: "old.swift",
            patch: "@@ -1,2 +1,2 @@\n-let x = 1\n+let y = system(cmd)\n+let z = 2\n context"
        )
        XCTAssertEqual(
            PRDiffSummary.summary(for: file),
            "+2  \u{2212}1 (was old.swift)  \u{2022}  1 line(s) worth reading closely"
        )
        XCTAssertEqual(SuspiciousLine.flagged(file), ["let y = system(cmd)"])
    }

    func testSummaryWithoutRenameOrFlags() {
        let file = changedFile(oldPath: nil, patch: "@@ -0,0 +1 @@\n+print(1)")
        XCTAssertEqual(PRDiffSummary.summary(for: file), "+1  \u{2212}0")
    }

    func testSuspiciousLinePatterns() {
        XCTAssertTrue(SuspiciousLine.isSuspicious("requests.get(\"http://x\")"))
        XCTAssertFalse(SuspiciousLine.isSuspicious("let a = 1"))
    }
}
