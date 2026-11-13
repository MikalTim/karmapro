import XCTest
@testable import KarmaCore

/// Pins the behaviour of the scan-window logic moved into KarmaCore: triage
/// prompt and verdict handling, the ignore list, and the table comparators.
final class ScanWindowLogicTests: XCTestCase {

    private func finding(file: String = "/p/a.c", line: Int = 1, function: String = "main",
                         category: String = "Buffer Overflow", message: String = "unsafe copy",
                         severity: ScanFinding.Severity = .high,
                         exploitability: ScanFinding.Severity = .high,
                         source: String = "AST", crossFile: Bool = false, taintPath: String? = nil) -> ScanFinding {
        ScanFinding(fileURL: URL(fileURLWithPath: file), line: line, function: function,
                    category: category, message: message, taint: nil, severity: severity,
                    exploitability: exploitability, reachable: true, taintPath: taintPath,
                    ignored: false, scanningSource: source, crossFile: crossFile)
    }

    private func writeSource(lines count: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-logic-\(UUID().uuidString).c")
        let text = (1...count).map { "line\($0)" }.joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Triage verdicts

    func testParseVerdictReadsValidAndInvalid() {
        XCTAssertEqual(ScanTriage.parseVerdict("VALID"), true)
        XCTAssertEqual(ScanTriage.parseVerdict("valid"), true)
        XCTAssertEqual(ScanTriage.parseVerdict("INVALID"), false)
        XCTAssertEqual(ScanTriage.parseVerdict("  invalid.\n"), false)
    }

    func testParseVerdictPrefersInvalidWhenBothWordsAppear() {
        XCTAssertEqual(ScanTriage.parseVerdict("INVALID, not VALID"), false)
    }

    func testParseVerdictRejectsMalformedAnswers() {
        XCTAssertNil(ScanTriage.parseVerdict(""))
        XCTAssertNil(ScanTriage.parseVerdict("   "))
        XCTAssertNil(ScanTriage.parseVerdict("I cannot decide."))
        XCTAssertNil(ScanTriage.parseVerdict("{\"verdict\": 1}"))
    }

    // MARK: - Transient failure detection

    func testRateLimitAndServerErrorsAreTransient() {
        XCTAssertTrue(ScanTriage.isTransientFailure(error("HTTP 429 Too Many Requests")))
        XCTAssertTrue(ScanTriage.isTransientFailure(error("rate limit reached")))
        XCTAssertTrue(ScanTriage.isTransientFailure(error("upstream returned 503")))
        XCTAssertTrue(ScanTriage.isTransientFailure(error("The request timed out")))
        XCTAssertTrue(ScanTriage.isTransientFailure(error("network connection lost")))
        XCTAssertTrue(ScanTriage.isTransientFailure(error("model is overloaded")))
    }

    func testKeyAndModelErrorsAreNotTransient() {
        XCTAssertFalse(ScanTriage.isTransientFailure(error("401 unauthorized")))
        XCTAssertFalse(ScanTriage.isTransientFailure(error("insufficient credits (402)")))
        XCTAssertFalse(ScanTriage.isTransientFailure(error("model not found")))
        XCTAssertFalse(ScanTriage.isTransientFailure(error("no API key configured")))
    }

    func testNonTransientMarkerWinsOverTransientMarker() {
        XCTAssertFalse(ScanTriage.isTransientFailure(error("503 not found")))
    }

    func testUnknownErrorIsNotTransient() {
        XCTAssertFalse(ScanTriage.isTransientFailure(error("The operation could not be completed.")))
    }

    private func error(_ message: String) -> Error {
        NSError(domain: "ScanWindowLogicTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - Triage prompt and snippet

    func testPromptContainsMetadataAndSnippetAroundTheLine() throws {
        let url = try writeSource(lines: 30)
        defer { try? FileManager.default.removeItem(at: url) }
        let prompt = ScanTriage.prompt(for: finding(file: url.path, line: 10))

        XCTAssertTrue(prompt.hasPrefix("Category: Buffer Overflow\nSeverity: High\nMessage: unsafe copy\n"))
        XCTAssertTrue(prompt.contains("Function: main\nFile: \(url.path)\nLine: 10\n"))
        XCTAssertTrue(prompt.contains("Code around the line:\n"))
        XCTAssertTrue(prompt.contains(">>> 10| line10"))
        XCTAssertTrue(prompt.contains("    1| line1"))
        XCTAssertTrue(prompt.hasSuffix("Answer with VALID or INVALID only."))
    }

    func testPromptOmitsSnippetWhenFileIsMissing() {
        let prompt = ScanTriage.prompt(for: finding(file: "/nonexistent/scan-logic.c", line: 3))
        XCTAssertFalse(prompt.contains("Code around the line"))
        XCTAssertTrue(prompt.hasSuffix("Answer with VALID or INVALID only."))
    }

    func testPromptIncludesDataFlowOnlyWhenPresent() {
        let withFlow = finding(file: "/nonexistent/scan-logic.c", taintPath: "argv[1] → buf")
        XCTAssertTrue(ScanTriage.prompt(for: withFlow).contains("Data flow: argv[1] → buf\n"))
        XCTAssertFalse(ScanTriage.prompt(for: finding(file: "/nonexistent/scan-logic.c"))
            .contains("Data flow"))
    }

    func testCodeSnippetWindowIsClampedToTheFile() throws {
        let url = try writeSource(lines: 100)
        defer { try? FileManager.default.removeItem(at: url) }

        let middle = try XCTUnwrap(ScanTriage.codeSnippet(for: finding(file: url.path, line: 50)))
        let middleLines = middle.components(separatedBy: "\n")
        XCTAssertEqual(middleLines.count, 46)
        XCTAssertEqual(middleLines.first, "    30| line30")
        XCTAssertEqual(middleLines.last, "    75| line75")
        XCTAssertTrue(middle.contains(">>> 50| line50"))

        let top = try XCTUnwrap(ScanTriage.codeSnippet(for: finding(file: url.path, line: 1)))
        let topLines = top.components(separatedBy: "\n")
        XCTAssertEqual(topLines.first, ">>> 1| line1")
        XCTAssertEqual(topLines.last, "    26| line26")
    }

    func testCodeSnippetSkipsFilesAtOrAboveOneMegabyte() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-logic-big-\(UUID().uuidString).c")
        try String(repeating: "a", count: 1_000_000).write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(ScanTriage.codeSnippet(for: finding(file: url.path, line: 1)))
    }

    // MARK: - Ignore list

    func testIgnoreListRoundTripsThroughUserDefaults() throws {
        let suite = "ScanWindowLogicTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "ScanWindowController.ignoredLines"

        let hidden = finding(file: "/p/a.c", line: 7)
        let shown = finding(file: "/p/a.c", line: 8)
        let list = FindingIgnoreList(defaultsKey: key, defaults: defaults)

        XCTAssertEqual(FindingIgnoreList.key(for: hidden), "/p/a.c#7")
        XCTAssertEqual(list.apply([hidden, shown]).map(\.line), [7, 8])

        list.ignore(hidden)
        XCTAssertEqual(defaults.stringArray(forKey: key), ["/p/a.c#7"])
        XCTAssertEqual(list.keys, ["/p/a.c#7"])
        XCTAssertEqual(list.apply([hidden, shown]).map(\.line), [8])

        // A new list over the same defaults sees the persisted key.
        let reloaded = FindingIgnoreList(defaultsKey: key, defaults: defaults)
        XCTAssertEqual(reloaded.apply([hidden, shown]).map(\.line), [8])

        reloaded.unignore(hidden)
        XCTAssertEqual(list.apply([hidden, shown]).map(\.line), [7, 8])
    }

    func testIgnoreListKeepsOtherDefaultsKeysSeparate() throws {
        let suite = "ScanWindowLogicTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        FindingIgnoreList(defaultsKey: "A", defaults: defaults).ignore(finding(line: 3))
        XCTAssertTrue(FindingIgnoreList(defaultsKey: "B", defaults: defaults).keys.isEmpty)
    }

    // MARK: - AI rows

    func testIsAIRowMatchesEngineNamesExactly() {
        XCTAssertTrue(ScanFindingSort.isAIRow(finding(source: "AI")))
        XCTAssertTrue(ScanFindingSort.isAIRow(finding(source: "Heuristic, AI")))
        XCTAssertTrue(ScanFindingSort.isAIRow(finding(source: "AI , AST")))
        XCTAssertFalse(ScanFindingSort.isAIRow(finding(source: "AIX")))
        XCTAssertFalse(ScanFindingSort.isAIRow(finding(source: "Heuristic")))
    }

    // MARK: - Column comparators

    private var early: ScanFinding {
        finding(file: "/p/b.c", line: 2, function: "beta", category: "Bee",
                severity: .low, exploitability: .low, source: "AST", crossFile: false)
    }
    private var late: ScanFinding {
        finding(file: "/q/a.c", line: 10, function: "alpha", category: "Ant",
                severity: .critical, exploitability: .critical,
                source: "Heuristic", crossFile: true)
    }

    private func compare(_ a: ScanFinding, _ b: ScanFinding, _ key: String,
                         ascending: Bool) -> ComparisonResult {
        ScanFindingSort.compare(a, b, key: key, ascending: ascending)
    }

    func testNumericColumnsSortByValueInBothDirections() {
        XCTAssertEqual(compare(early, late, "line", ascending: true), .orderedAscending)
        XCTAssertEqual(compare(early, late, "line", ascending: false), .orderedDescending)
        XCTAssertEqual(compare(early, late, "severity", ascending: true), .orderedAscending)
        XCTAssertEqual(compare(early, late, "severity", ascending: false), .orderedDescending)
        XCTAssertEqual(compare(early, late, "exploitability", ascending: true), .orderedAscending)
        XCTAssertEqual(compare(early, late, "exploitability", ascending: false), .orderedDescending)
    }

    func testEngineAndCrossFileColumnsSortByValueInBothDirections() {
        XCTAssertEqual(compare(early, late, "scanningSource", ascending: true), .orderedAscending)
        XCTAssertEqual(compare(early, late, "scanningSource", ascending: false), .orderedDescending)
        // false sorts before true.
        XCTAssertEqual(compare(early, late, "crossFile", ascending: true), .orderedAscending)
        XCTAssertEqual(compare(early, late, "crossFile", ascending: false), .orderedDescending)
    }

    func testFileColumnSortsByLastPathComponent() {
        // "a.c" (late) sorts before "b.c" (early).
        XCTAssertEqual(compare(early, late, "fileURL", ascending: true), .orderedDescending)
        XCTAssertEqual(compare(early, late, "fileURL", ascending: false), .orderedAscending)
    }

    func testTextColumnsSortByDisplayText() {
        // "Ant" (late) sorts before "Bee" (early).
        XCTAssertEqual(compare(early, late, "category", ascending: true), .orderedDescending)
        XCTAssertEqual(compare(early, late, "category", ascending: false), .orderedAscending)
        // "alpha" (late) sorts before "beta" (early).
        XCTAssertEqual(compare(early, late, "function", ascending: true), .orderedDescending)
        XCTAssertEqual(compare(early, late, "function", ascending: false), .orderedAscending)
    }

    func testEqualValuesAreTiedInBothDirections() {
        let twin = finding(file: "/other/dir/b.c", line: 2, function: "beta", category: "Bee",
                           severity: .low, exploitability: .low, source: "AST", crossFile: false)
        for key in ["line", "severity", "exploitability", "scanningSource", "crossFile",
                    "fileURL", "category", "function"] {
            XCTAssertEqual(compare(early, twin, key, ascending: true), .orderedSame, key)
            XCTAssertEqual(compare(early, twin, key, ascending: false), .orderedSame, key)
        }
    }

    func testUnknownKeysTieBecauseTheirDisplayTextIsEmpty() {
        XCTAssertEqual(compare(early, late, "inpr", ascending: true), .orderedSame)
        XCTAssertEqual(compare(early, late, "msg", ascending: false), .orderedSame)
        XCTAssertEqual(ScanFindingSort.displayText(for: "inpr", finding: early), "")
    }

    func testDisplayTextForTextualKeys() {
        XCTAssertEqual(ScanFindingSort.displayText(for: "category", finding: early), "Bee")
        XCTAssertEqual(ScanFindingSort.displayText(for: "function", finding: early), "beta")
        XCTAssertEqual(ScanFindingSort.displayText(for: "fileURL", finding: early), "b.c")
        XCTAssertEqual(ScanFindingSort.displayText(for: "crossFile", finding: early), "No")
        XCTAssertEqual(ScanFindingSort.displayText(for: "crossFile", finding: late), "Yes")
    }

    func testSortingWithTiesFallsThroughToTheNextKey() {
        // Same severity, different lines: the line decides the order.
        let first = finding(line: 4, severity: .medium)
        let second = finding(line: 9, severity: .medium)
        let sorted = [second, first].sorted { a, b in
            var result = ComparisonResult.orderedSame
            for key in ["severity", "line"] {
                result = ScanFindingSort.compare(a, b, key: key, ascending: true)
                if result != .orderedSame { break }
            }
            return result == .orderedAscending
        }
        XCTAssertEqual(sorted.map(\.line), [4, 9])
    }
}
