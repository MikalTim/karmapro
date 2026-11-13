import Foundation
import XCTest
@testable import KarmaCore

/// The Security Scan window's state as the service reports it for a project scan.
final class SecurityScanServiceTests: XCTestCase {

    private static let vulnerableC = """
        #include <stdio.h>
        #include <string.h>
        #include <stdlib.h>
        int main(int argc, char **argv) {
            char buf[16];
            strcpy(buf, argv[1]);
            system(getenv("CMD"));
            printf(argv[2]);
            return 0;
        }
        """

    override func tearDown() {
        KarmaWorkspace.shared.close()
        super.tearDown()
    }

    private func waitForJob(_ id: String, timeout: TimeInterval = 30,
                            file: StaticString = #filePath, line: UInt = #line) -> JobDTO? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let job = KarmaJobCenter.shared.job(id), job.status != "running" { return job }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTFail("scan job \(id) did not finish", file: file, line: line)
        return nil
    }

    func testScanningWithoutAProjectIsRefused() {
        KarmaWorkspace.shared.close()
        XCTAssertThrowsError(try SecurityScanService().start(wantsAI: false)) { error in
            XCTAssertEqual(error.localizedDescription, "No Folder Open: choose a project folder first.")
        }
        XCTAssertThrowsError(try SecurityScanService().scanPrompt())
    }

    func testScanListsFindingsWithProjectRelativePathsAndOffersExport() throws {
        let fixture = try ScanFixture(["src/vuln.c": Self.vulnerableC])
        try KarmaWorkspace.shared.open(root: fixture.root.path)
        let service = SecurityScanService()

        let job = try XCTUnwrap(waitForJob(try service.start(wantsAI: false)))

        XCTAssertEqual(job.status, "completed")
        let state = service.state()
        XCTAssertEqual(state.title, "Security Scan")
        XCTAssertFalse(state.showPullRequestColumn)
        XCTAssertTrue(state.canRescan)
        XCTAssertTrue(state.canExport)
        XCTAssertTrue(state.status.hasPrefix("Scan complete: "), state.status)
        XCTAssertEqual(state.rows.count, Set(state.rows.map(\.key)).count)
        let overflow = try XCTUnwrap(state.rows.first { $0.category == "Buffer Overflow" })
        XCTAssertEqual(overflow.displayPath, "src/vuln.c")
        XCTAssertEqual(overflow.line, 6)
        XCTAssertEqual(overflow.key, "\(overflow.path)#6")

        let export = try service.export()
        XCTAssertEqual(export.fileName, "KarmaPro-scan.sarif.json")
        XCTAssertTrue(String(decoding: export.data, as: UTF8.self).contains("2.1.0"))
    }

    func testSecondPlainScanShowsTheCachedResultsAndRescanRunsAgain() throws {
        let fixture = try ScanFixture(["vuln.c": Self.vulnerableC])
        try KarmaWorkspace.shared.open(root: fixture.root.path)
        let service = SecurityScanService()
        _ = waitForJob(try service.start(wantsAI: false))
        let found = service.state().rows.count
        XCTAssertGreaterThan(found, 0)

        _ = waitForJob(try service.start(wantsAI: false))
        XCTAssertEqual(service.state().status,
                       "Showing cached scan: \(found) potential issue\(found == 1 ? "" : "s") \u{2014} Rescan to refresh.")

        _ = waitForJob(try service.rescan())
        XCTAssertTrue(service.state().status.hasPrefix("Scan complete: "))
        XCTAssertEqual(service.state().rows.count, found)
    }

    func testSortOrderAppliesToTheRows() throws {
        let fixture = try ScanFixture(["vuln.c": Self.vulnerableC])
        try KarmaWorkspace.shared.open(root: fixture.root.path)
        let service = SecurityScanService()
        _ = waitForJob(try service.start(wantsAI: false))

        service.setSort([SecurityScanService.SortKeyDTO(key: "line", ascending: false)])
        let descending = service.state().rows.map(\.line)
        service.setSort([SecurityScanService.SortKeyDTO(key: "line", ascending: true)])
        let ascending = service.state().rows.map(\.line)

        XCTAssertGreaterThan(ascending.count, 1)
        XCTAssertEqual(ascending, ascending.sorted())
        XCTAssertEqual(descending, descending.sorted(by: >))
    }
}
