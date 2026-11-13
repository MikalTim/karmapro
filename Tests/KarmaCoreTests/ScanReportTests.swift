import XCTest
import KarmaCore

/// The public, Codable report that front ends (CLI, web server) consume.
/// Uses only the public API, as an external front end would.
final class ScanReportTests: XCTestCase {

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-report-\(UUID().uuidString)", isDirectory: true)
        let sub = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try """
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
            """.write(to: sub.appendingPathComponent("vuln.c"), atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testReportDescribesTheScan() throws {
        let report = KarmaScanner.scan(root: try makeProject())
        XCTAssertFalse(report.cancelled)
        XCTAssertEqual(report.filesScanned, 1)
        XCTAssertEqual(Set(report.findings.map(\.file)), ["src/vuln.c"])
        XCTAssertEqual(report.summary.total, report.findings.count)
        XCTAssertEqual(report.summary.bySeverity["high"], report.findings.filter { $0.severity == .high }.count)
        XCTAssertEqual(report.summary.bySeverity["medium"], 1)
        XCTAssertEqual(report.summary.bySeverity["critical"], 0)
        XCTAssertEqual(report.summary.byCategory["Format String"], 1)
        let format = try XCTUnwrap(report.findings.first { $0.category == "Format String" })
        XCTAssertEqual(format.line, 8)
        XCTAssertEqual(format.function, "main")
        XCTAssertEqual(format.engine, "AST")
    }

    func testJSONRoundTrips() throws {
        let report = KarmaScanner.scan(root: try makeProject())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var decoded = try decoder.decode(ScanReport.self, from: report.jsonData())
        // ISO-8601 keeps whole seconds only.
        XCTAssertEqual(decoded.startedAt.timeIntervalSince1970, report.startedAt.timeIntervalSince1970, accuracy: 1)
        decoded.startedAt = report.startedAt
        XCTAssertEqual(decoded, report)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: report.jsonData(pretty: false)) as? [String: Any])
        XCTAssertEqual(Set(object.keys),
                       ["root", "startedAt", "durationSeconds", "cancelled", "filesScanned", "summary", "findings"])
        let first = try XCTUnwrap((object["findings"] as? [[String: Any]])?.first)
        XCTAssertNotNil(first["severity"] as? String)
        XCTAssertNotNil(first["engine"] as? String)
    }

    func testMinimumSeverityFilterRecomputesSummary() throws {
        let report = KarmaScanner.scan(root: try makeProject())
        let high = report.filtered(minimumSeverity: .high)
        XCTAssertFalse(high.findings.isEmpty)
        XCTAssertTrue(high.findings.allSatisfy { $0.severity == .high || $0.severity == .critical })
        XCTAssertEqual(high.summary.total, high.findings.count)
        XCTAssertEqual(high.summary.bySeverity["medium"], 0)
        XCTAssertEqual(report.filtered(minimumSeverity: .low), report)
    }

    func testCancelledScanIsFlagged() throws {
        let report = KarmaScanner.scan(root: try makeProject(), isCancelled: { true })
        XCTAssertTrue(report.cancelled)
        XCTAssertTrue(report.findings.isEmpty)
    }
}
