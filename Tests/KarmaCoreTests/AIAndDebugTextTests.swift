import XCTest
@testable import KarmaCore

/// Pins the behaviour of the AI chat text helpers and the simulator's
/// parameter parser, moved out of the AppKit controllers.
final class AIAndDebugTextTests: XCTestCase {

    // MARK: - AIChatText.splitSettledStream

    func testSplitEmptyText() {
        let split = AIChatText.splitSettledStream("")
        XCTAssertEqual(split.settled, "")
        XCTAssertEqual(split.live, "")
    }

    func testSplitWithoutBlankLineIsAllLive() {
        let split = AIChatText.splitSettledStream("Hello **world**")
        XCTAssertEqual(split.settled, "")
        XCTAssertEqual(split.live, "Hello **world**")
    }

    func testSplitAtBlankLineKeepsSeparatorWithSettledPart() {
        let split = AIChatText.splitSettledStream("A\n\nB")
        XCTAssertEqual(split.settled, "A\n\n")
        XCTAssertEqual(split.live, "B")
    }

    func testSplitWhenTextEndsOnBlankLineLeavesNoLiveTail() {
        let split = AIChatText.splitSettledStream("A\n\nB\n")
        XCTAssertEqual(split.settled, "A\n\nB\n")
        XCTAssertEqual(split.live, "")
    }

    func testUnclosedFenceHoldsEverythingBack() {
        let text = "```swift\nlet x = 1\n\nmore"
        let split = AIChatText.splitSettledStream(text)
        XCTAssertEqual(split.settled, "")
        XCTAssertEqual(split.live, text)
    }

    func testBlankLineInsideOpenFenceIsNotABoundary() {
        let split = AIChatText.splitSettledStream("A\n\n```\nx\n\ny")
        XCTAssertEqual(split.settled, "A\n\n")
        XCTAssertEqual(split.live, "```\nx\n\ny")
    }

    func testClosedFenceThenBlankLineSettlesTheFence() {
        let split = AIChatText.splitSettledStream("```\ncode\n```\n\nafter")
        XCTAssertEqual(split.settled, "```\ncode\n```\n\n")
        XCTAssertEqual(split.live, "after")
    }

    func testWhitespaceOnlyLineCountsAsBlank() {
        let split = AIChatText.splitSettledStream("A\n  \nB")
        XCTAssertEqual(split.settled, "A\n  \n")
        XCTAssertEqual(split.live, "B")
    }

    // MARK: - AIChatText.toolDisplayLabel

    func testToolLabelSortsArgumentsByKey() {
        let label = AIChatText.toolDisplayLabel(name: "read_file",
                                                args: "{\"path\":\"a.c\",\"line\":3}")
        XCTAssertEqual(label, "$ read_file(line: 3, path: a.c)")
    }

    func testToolLabelWithEmptyArgumentsHasNoParentheses() {
        XCTAssertEqual(AIChatText.toolDisplayLabel(name: "list_files", args: "{}"), "$ list_files")
    }

    func testToolLabelWithInvalidArgumentsHasNoParentheses() {
        XCTAssertEqual(AIChatText.toolDisplayLabel(name: "search_files", args: "not json"),
                       "$ search_files")
    }

    // MARK: - AIChatText.toolDisplayOutput

    func testToolOutputError() {
        XCTAssertEqual(AIChatText.toolDisplayOutput("{\"error\":\"denied\"}"), "error: denied")
    }

    func testToolOutputJoinsLinesWithReturnSymbol() {
        XCTAssertEqual(AIChatText.toolDisplayOutput("{\"output\":\"a\\nb\\n\"}"), "a ⏎ b")
    }

    func testToolOutputBlankCommandOutput() {
        XCTAssertEqual(AIChatText.toolDisplayOutput("{\"output\":\" \\n \"}"), "(no output)")
    }

    func testToolOutputEmptyEntries() {
        XCTAssertEqual(AIChatText.toolDisplayOutput("{\"entries\":[]}"), "(empty)")
    }

    func testToolOutputEntriesListsFirstTwelve() {
        XCTAssertEqual(AIChatText.toolDisplayOutput("{\"entries\":[\"a\",\"b\"]}"), "2 entries: a, b")
        let thirteen = "{\"entries\":[\"f1\",\"f2\",\"f3\",\"f4\",\"f5\",\"f6\",\"f7\",\"f8\",\"f9\",\"f10\",\"f11\",\"f12\",\"f13\"]}"
        XCTAssertEqual(AIChatText.toolDisplayOutput(thirteen),
                       "13 entries: f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, …")
    }

    func testToolOutputMatches() {
        XCTAssertEqual(AIChatText.toolDisplayOutput("{\"matches\":[]}"), "no matches")
        XCTAssertEqual(AIChatText.toolDisplayOutput("{\"matches\":[\"x\",\"y\",\"z\"]}"), "3 matches")
    }

    func testToolOutputReadCountsCharacters() {
        XCTAssertEqual(AIChatText.toolDisplayOutput("{\"content\":\"héllo\"}"), "read 5 chars")
    }

    func testToolOutputOk() {
        XCTAssertEqual(AIChatText.toolDisplayOutput("{\"ok\":true}"), "ok")
    }

    func testToolOutputUnknownJSONFallsBackToRawText() {
        XCTAssertEqual(AIChatText.toolDisplayOutput("{\"other\":1}"), "{\"other\":1}")
    }

    func testToolOutputNonJSONIsTruncatedTo300Characters() {
        let long = String(repeating: "a", count: 400)
        XCTAssertEqual(AIChatText.toolDisplayOutput(long).count, 300)
        XCTAssertEqual(AIChatText.toolDisplayOutput("plain text"), "plain text")
    }

    // MARK: - AIChatText.systemPrompt

    func testSystemPromptWithoutProjectOmitsDirectory() {
        let prompt = AIChatText.systemPrompt(projectRoot: nil)
        XCTAssertTrue(prompt.hasPrefix("You are a senior software analysis assistant embedded in Karma Pro, a static-analysis IDE."))
        XCTAssertFalse(prompt.contains("The user's project directory is:"))
        XCTAssertFalse(prompt.contains("relative to that directory"))
        XCTAssertTrue(prompt.contains("run_command"))
    }

    func testSystemPromptNamesProjectDirectory() {
        let prompt = AIChatText.systemPrompt(projectRoot: URL(fileURLWithPath: "/tmp/demo"))
        XCTAssertTrue(prompt.contains("The user's project directory is: /tmp/demo"))
        XCTAssertTrue(prompt.contains("File paths in the conversation are relative to that directory."))
    }

    // MARK: - SimParameterSeed.parse

    private func seed(isBuffer: Bool = false, capacity: Int = 0) -> SimParameterSeed {
        SimParameterSeed(name: "p", typeHint: "int", value: .int(0),
                         isBuffer: isBuffer, capacity: capacity)
    }

    func testParseIntegers() {
        XCTAssertEqual(seed().parse(" 42 "), .int(42))
        XCTAssertEqual(seed().parse("-7"), .int(-7))
    }

    func testParseBooleans() {
        XCTAssertEqual(seed().parse("true"), .bool(true))
        XCTAssertEqual(seed().parse("false"), .bool(false))
    }

    func testParseDecimal() {
        XCTAssertEqual(seed().parse("3.5"), .double(3.5))
    }

    func testParseQuotedString() {
        XCTAssertEqual(seed().parse("\"hi there\""), .string("hi there"))
    }

    func testParseInvalidInputBecomesBareString() {
        XCTAssertEqual(seed().parse("hello"), .string("hello"))
        XCTAssertEqual(seed().parse("1e3"), .string("1e3"))
        XCTAssertEqual(seed().parse("1.2.3"), .string("1.2.3"))
        XCTAssertEqual(seed().parse("12abc"), .string("12abc"))
        XCTAssertEqual(seed().parse(""), .string(""))
        XCTAssertEqual(seed().parse("\""), .string("\""))
    }

    func testParseBufferStripsOneQuotePairAndKeepsCapacity() {
        XCTAssertEqual(seed(isBuffer: true, capacity: 8).parse("\"hello\""),
                       .buffer("hello", capacity: 8))
        XCTAssertEqual(seed(isBuffer: true, capacity: 8).parse("  abc  "),
                       .buffer("abc", capacity: 8))
        XCTAssertEqual(seed(isBuffer: true, capacity: 8).parse("12345"),
                       .buffer("12345", capacity: 8))
    }
}
