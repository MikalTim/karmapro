import Foundation
import XCTest
@testable import KarmaCore

/// Pins the behaviour of the package-scan rows and comparators, and of the
/// ML project scanner, as moved into KarmaCore.
final class PackageScanFindingsTests: XCTestCase {

    private let lockfile = URL(fileURLWithPath: "/p/package-lock.json")

    private func vulnerability(_ json: String) throws -> OSVVulnerability {
        try JSONDecoder().decode(OSVVulnerability.self, from: Data(json.utf8))
    }

    private func finding(package: String?, line: Int = 1, file: String = "/p/a.json",
                         category: String = "GHSA-x", message: String = "m",
                         severity: ScanFinding.Severity = .high) -> ScanFinding {
        ScanFinding(fileURL: URL(fileURLWithPath: file), line: line, function: "npm",
                    category: category, message: message, taint: nil, severity: severity,
                    exploitability: severity, reachable: true, taintPath: nil,
                    ignored: false, scanningSource: "OSV", crossFile: false, packageName: package)
    }

    // MARK: - Rows

    func testMakeBuildsRowsSortedBySeverityThenPackageThenId() throws {
        let zeta = PackageDependency(name: "zeta", version: "1.0", ecosystem: "npm", fileURL: lockfile, line: 3)
        let alpha = PackageDependency(name: "alpha", version: "2.0", ecosystem: "npm", fileURL: lockfile, line: 5)
        let clean = PackageDependency(name: "clean", version: "1.0", ecosystem: "npm", fileURL: lockfile, line: 7)

        let zetaVulns = [
            try vulnerability(#"{"id":"GHSA-1","summary":"Bad thing","aliases":["GHSA-x","CVE-2024-1"],"database_specific":{"severity":"HIGH"}}"#),
            try vulnerability(#"{"id":"GHSA-0","summary":"Low one","database_specific":{"severity":"LOW"}}"#),
            try vulnerability(#"{"id":"GHSA-3","summary":"","details":"Another\nmore","database_specific":{"severity":"HIGH"}}"#),
        ]
        let alphaVulns = [
            try vulnerability(#"{"id":"GHSA-2","summary":null,"details":"First line\nsecond","database_specific":{"severity":"CRITICAL"}}"#),
        ]
        let vulns: [String: [OSVVulnerability]] = [
            OSVClient.queryKey(ecosystem: "npm", name: "zeta", version: "1.0"): zetaVulns,
            OSVClient.queryKey(ecosystem: "npm", name: "alpha", version: "2.0"): alphaVulns,
        ]

        let rows = PackageScanFindings.make(dependencies: [zeta, alpha, clean], vulnerabilities: vulns)

        XCTAssertEqual(rows.map { $0.category }, ["GHSA-2", "GHSA-1", "GHSA-3", "GHSA-0"])
        XCTAssertEqual(rows.map { $0.severity }, [.critical, .high, .high, .low])
        XCTAssertEqual(rows.map { $0.message }, [
            "GHSA-2: First line",
            "CVE-2024-1: Bad thing",
            "GHSA-3: Another",
            "GHSA-0: Low one",
        ])
        XCTAssertEqual(rows.map { $0.packageName }, ["alpha@2.0", "zeta@1.0", "zeta@1.0", "zeta@1.0"])
        XCTAssertEqual(rows.map { $0.line }, [5, 3, 3, 3])
        XCTAssertTrue(rows.allSatisfy { $0.function == "npm" && $0.scanningSource == "OSV" && $0.fileURL == lockfile })
    }

    // MARK: - Comparators

    private func assertOrdered(_ a: ScanFinding, _ b: ScanFinding, key: String,
                               sourceLine: UInt = #line) {
        XCTAssertEqual(PackageScanFindings.compare(a, b, key: key, ascending: true), .orderedAscending,
                       "\(key) ascending", line: sourceLine)
        XCTAssertEqual(PackageScanFindings.compare(a, b, key: key, ascending: false), .orderedDescending,
                       "\(key) descending", line: sourceLine)
        XCTAssertEqual(PackageScanFindings.compare(b, a, key: key, ascending: true), .orderedDescending,
                       "\(key) reversed ascending", line: sourceLine)
        XCTAssertEqual(PackageScanFindings.compare(b, a, key: key, ascending: false), .orderedAscending,
                       "\(key) reversed descending", line: sourceLine)
    }

    func testCompareOrdersEachKeyInBothDirections() {
        let low = finding(package: "a@1", line: 2, file: "/p/a.json", category: "X", message: "apple", severity: .low)
        let high = finding(package: "b@1", line: 9, file: "/p/z.json", category: "Y", message: "zebra", severity: .critical)

        assertOrdered(low, high, key: "severity")
        assertOrdered(low, high, key: "package")
        assertOrdered(low, high, key: "fileURL")
        assertOrdered(low, high, key: "line")
        assertOrdered(low, high, key: "message")
        assertOrdered(low, high, key: "unknown-column")
    }

    func testCompareReturnsSameForTiesInBothDirections() {
        let a = finding(package: "a@1", line: 2, file: "/p/a.json", category: "X", message: "apple", severity: .low)
        let twin = finding(package: "a@1", line: 2, file: "/p/a.json", category: "Z", message: "apple", severity: .low)

        for key in ["severity", "package", "fileURL", "line", "message", "unknown-column"] {
            XCTAssertEqual(PackageScanFindings.compare(a, twin, key: key, ascending: true), .orderedSame, key)
            XCTAssertEqual(PackageScanFindings.compare(a, twin, key: key, ascending: false), .orderedSame, key)
        }
    }

    // MARK: - Ignore list

    func testIgnoredRowsAreKeyedByPackageAndPersistInDefaults() {
        let suite = "PackageAndMLScanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let hidden = finding(package: "a@1", line: 4, file: "/p/a.json")
        let otherPackage = finding(package: "b@1", line: 4, file: "/p/a.json")

        XCTAssertEqual(PackageScanFindings.ignoredKey(for: hidden), "/p/a.json#4#a@1")
        XCTAssertTrue(PackageScanFindings.ignoredLines(defaults: defaults).isEmpty)

        PackageScanFindings.setIgnoredLines([PackageScanFindings.ignoredKey(for: hidden)], defaults: defaults)

        XCTAssertEqual(PackageScanFindings.applyIgnored([hidden, otherPackage], defaults: defaults).map { $0.packageName },
                       ["b@1"])
        XCTAssertEqual(defaults.stringArray(forKey: "PackageScanWindowController.ignoredLines"),
                       ["/p/a.json#4#a@1"])
    }
}

final class BayesianProjectScannerTests: XCTestCase {

    private func check(_ line: String, inBlock: Bool, comment: Bool, stillInBlock: Bool,
                       sourceLine: UInt = #line) {
        let result = BayesianProjectScanner.isCommentLine(line, inBlockComment: inBlock)
        XCTAssertEqual(result.0, comment, "isComment for \"\(line)\"", line: sourceLine)
        XCTAssertEqual(result.1, stillInBlock, "block state after \"\(line)\"", line: sourceLine)
    }

    func testIsCommentLineHandlesLineAndBlockComments() {
        check("  // note", inBlock: false, comment: true, stillInBlock: false)
        check("x = 1; // trailing", inBlock: false, comment: false, stillInBlock: false)
        check("/x", inBlock: false, comment: false, stillInBlock: false)
        check("/* open", inBlock: false, comment: true, stillInBlock: true)
        check("still inside", inBlock: true, comment: true, stillInBlock: true)
        check("end */", inBlock: true, comment: true, stillInBlock: false)
        check("*/ x = 1", inBlock: true, comment: false, stillInBlock: false)
        check("/* a */ b", inBlock: false, comment: false, stillInBlock: false)
        check("", inBlock: false, comment: true, stillInBlock: false)
    }

    func testEnumerateSourceFilesHonoursExtensionsAndSkippedFolders() throws {
        let project = try ScanFixture([
            "src/a.c": "",
            "src/b.py": "",
            "sub/f.C": "",
            "build/c.c": "",
            "vendor/d.c": "",
            "node_modules/e.c": "",
        ])

        let byExtension = BayesianProjectScanner.enumerateSourceFiles(in: project.root, extensions: ["c"])
        XCTAssertEqual(Set(byExtension.map { $0.lastPathComponent }), ["a.c", "f.C"])

        // With no extension filter the walk also yields folder entries (as the original
        // SourceTree.enumerateAll does), so only the files and the skipped folders' contents are checked.
        let all = BayesianProjectScanner.enumerateSourceFiles(in: project.root, extensions: [])
        let names = Set(all.map { $0.lastPathComponent })
        XCTAssertTrue(names.isSuperset(of: ["a.c", "b.py", "f.C"]))
        XCTAssertTrue(names.isDisjoint(with: ["c.c", "d.c", "e.c"]))
    }

    func testScanProjectFlagsOnlyCodeLinesAboveThreshold() throws {
        let model = BayesianClassifier(name: "test")
        for _ in 0..<3 {
            model.train(line: "strcpy(buf, argv[1]);", isBad: true)
            model.train(line: "int total = count + 1;", isBad: false)
        }
        let project = try ScanFixture([
            "src/x.c": [
                "int total = count + 1;",
                "strcpy(buf, argv[1]);",
                "// strcpy(buf, argv[1]);",
                "/* strcpy(buf, argv[1]); */",
            ].joined(separator: "\n"),
            "src/notes.txt": "strcpy(buf, argv[1]);",
        ])

        let outcome = BayesianProjectScanner.scanProject(root: project.root, model: model,
                                                         extensions: ["c"], threshold: 0.5, progress: nil)

        XCTAssertEqual(outcome.totalFiles, 1)
        XCTAssertEqual(outcome.totalLines, 4)
        XCTAssertEqual(outcome.results.count, 1)
        let flagged = outcome.results.values.first ?? [:]
        XCTAssertEqual(Set(flagged.keys), [2], "comment lines and the non-matching line must not be flagged")
        XCTAssertGreaterThanOrEqual(flagged[2] ?? 0, 0.5)
    }
}
