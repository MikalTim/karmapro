import XCTest
@testable import KarmaCore

/// Project-level guarantees of `VulnerabilityScanner.scan` that the scanner
/// source documents: cross-file taint, dead-code suppression, de-duplication,
/// ordering, cancellation and the file-selection limits.
final class EngineBehaviourTests: XCTestCase {

    private static let liveC = """
        #include <string.h>
        static void helper(char *s) { char b[4]; strcpy(b, s); }
        int main(int argc, char **argv) { helper(argv[1]); return 0; }
        """

    func testCrossFileTaintIsMarked() throws {
        let fixture = try ScanFixture([
            "Util.java": """
                public class Util {
                    public static String read(javax.servlet.http.HttpServletRequest r) { return r.getParameter("p"); }
                }
                """,
            "Use.java": """
                public class Use {
                    public void go(javax.servlet.http.HttpServletRequest r) throws Exception {
                        String v = Util.read(r);
                        Runtime.getRuntime().exec(v);
                    }
                }
                """,
        ])
        let findings = fixture.scan()
        XCTAssertFinding(findings, file: "Use.java", line: 4, category: "Command Injection", severity: .high, engine: "AST")
        XCTAssertEqual(findings.first { $0.fileName == "Use.java" }?.crossFile, true)
    }

    func testUnreferencedStaticFunctionIsSuppressed() throws {
        let fixture = try ScanFixture([
            "live.c": Self.liveC,
            "dead.c": """
                #include <string.h>
                static void unused_helper(char *s) { char b[4]; strcpy(b, s); }
                int main(int argc, char **argv) { return 0; }
                """,
        ])
        let findings = fixture.scan()
        XCTAssertFinding(findings, file: "live.c", line: 2, category: "Buffer Overflow", severity: .high, engine: "AST")
        XCTAssertTrue(findings.filter { $0.fileName == "dead.c" }.isEmpty,
                      "dead static helper must not be reported: \(findings.map(\.category))")
    }

    func testConstantCommandIsNotInjection() throws {
        let fixture = try ScanFixture(["safe.c": """
            #include <stdlib.h>
            int main(void) { system("ls -la"); return 0; }
            """])
        XCTAssertFalse(fixture.scan().contains { $0.category == "Command Injection" })
    }

    func testUntaintedQualityRuleIsReportedOncePerFile() throws {
        // `hashlib.new("md5", …)` is flagged regardless of taint (the algorithm
        // literal is the defect), so both call sites produce taint-free rows.
        let fixture = try ScanFixture(["crypto.py": """
            import hashlib
            def a():
                return hashlib.new("md5", b"abc").hexdigest()
            def b():
                return hashlib.new("md5", b"def").hexdigest()
            a()
            b()
            """])
        let weak = fixture.scan().filter { $0.category == "Weak Cryptography" }
        XCTAssertEqual(weak.count, 1, "context-free weak crypto collapses to one row per file")
        XCTAssertNil(weak.first?.taintPath)
    }

    func testFindingsAreUniqueAndMostSevereFirst() throws {
        let fixture = try ScanFixture([
            "vuln.c": """
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
                """,
            "app.js": """
                const express = require('express');
                const app = express();
                app.get('/x', function handler(req, res) {
                  eval(req.query.code);
                });
                """,
        ])
        let findings = fixture.scan()
        XCTAssertGreaterThanOrEqual(findings.count, 4)
        let keys = findings.map { "\($0.fileName):\($0.line):\($0.category)" }
        XCTAssertEqual(Set(keys).count, keys.count, "duplicate (file, line, category): \(keys)")
        XCTAssertEqual(findings.map(\.severity), findings.map(\.severity).sorted(by: >))
        XCTAssertEqual(findings.first?.severity, .critical)
    }

    func testOnlySupportedSourceFilesAreScanned() throws {
        let fixture = try ScanFixture(["live.c": Self.liveC, "notes.txt": Self.liveC, "README.md": Self.liveC])
        var reportedTotal = 0
        let findings = fixture.scan(progress: { _, total in reportedTotal = total })
        XCTAssertEqual(reportedTotal, 1)
        XCTAssertEqual(Set(findings.map(\.fileName)), ["live.c"])
    }

    func testOversizedFileIsSkipped() throws {
        let padding = "/*" + String(repeating: "x", count: 1_000_001) + "*/\n"
        let fixture = try ScanFixture(["big.c": padding + Self.liveC, "live.c": Self.liveC])
        let findings = fixture.scan()
        XCTAssertEqual(Set(findings.map(\.fileName)), ["live.c"])
    }

    func testCancellationStopsBeforeAnyFile() throws {
        let fixture = try ScanFixture(["a.c": Self.liveC, "b.c": Self.liveC])
        var progressCalls = 0
        let findings = fixture.scan(progress: { _, _ in progressCalls += 1 }, isCancelled: { true })
        XCTAssertTrue(findings.isEmpty)
        XCTAssertEqual(progressCalls, 0)
    }
}
