import Foundation
import XCTest
@testable import KarmaCore

/// What the source viewer (AppKit and web) derives from a file's text.
final class SourceNavigationTests: XCTestCase {

    private let cSource = """
        int add(int a, int b) { return a + b; }
        void run(int n) {
            int x = add(1, 2);
            if (x > n) { x = sizeof(int); }
            while (x < 10) { x = x + add(x, 1); }
        }
        """

    private func text(_ source: String, _ range: NSRange) -> String {
        (source as NSString).substring(with: range)
    }

    func testFunctionDefinitionNamesAreFoundAsNameRanges() {
        let ranges = SourceNavigation.clickableRanges(source: cSource, fileExtension: "c")

        XCTAssertEqual(ranges.functions.map(\.name), ["add", "run"])
        for entry in ranges.functions {
            XCTAssertEqual(text(cSource, entry.range), entry.name)
        }
        XCTAssertTrue(ranges.classes.isEmpty)
    }

    func testUnsupportedExtensionHasNoClickableRanges() {
        let ranges = SourceNavigation.clickableRanges(source: "just text (really)", fileExtension: "txt")
        XCTAssertTrue(ranges.functions.isEmpty)
        XCTAssertTrue(ranges.classes.isEmpty)
    }

    func testClassNamesAreOnlyReportedForJavaAndCSharp() {
        let java = "public class Greeter {\n    void hello() { }\n}\n"
        let javaRanges = SourceNavigation.clickableRanges(source: java, fileExtension: "java")
        XCTAssertEqual(javaRanges.classes.map(\.name), ["Greeter"])
        XCTAssertEqual(text(java, javaRanges.classes[0].range), "Greeter")

        let cpp = "class Greeter { void hello() { } };\n"
        XCTAssertTrue(SourceNavigation.clickableRanges(source: cpp, fileExtension: "cpp").classes.isEmpty)
    }

    func testCallSitesSkipDefinitionsAndKeywords() {
        let defined = SourceNavigation.clickableRanges(source: cSource, fileExtension: "c")
        let sites = SourceNavigation.callSites(source: cSource,
                                               definitionRanges: defined.functions + defined.classes,
                                               isKnownName: { _ in true })

        // `add` is called twice in run(); the definition of add and run, the
        // keywords `if`/`while` and `sizeof(` are not call sites.
        XCTAssertEqual(sites.map(\.name), ["add", "add"])
        for site in sites {
            XCTAssertEqual(text(cSource, site.range), "add")
            XCTAssertFalse(defined.functions.contains { NSIntersectionRange($0.range, site.range).length > 0 })
        }
    }

    func testCallSitesOnlyIncludeNamesTheProjectDefines() {
        let defined = SourceNavigation.clickableRanges(source: cSource, fileExtension: "c")
        let sites = SourceNavigation.callSites(source: cSource,
                                               definitionRanges: defined.functions,
                                               isKnownName: { $0 == "nothing" })
        XCTAssertTrue(sites.isEmpty)
    }

    func testFunctionNameAtCharacterIndexUsesHalfOpenRanges() {
        let ranges = SourceNavigation.clickableRanges(source: cSource, fileExtension: "c").functions
        let first = ranges[0].range

        XCTAssertEqual(SourceNavigation.functionName(at: first.location, in: ranges), "add")
        XCTAssertEqual(SourceNavigation.functionName(at: first.location + first.length - 1, in: ranges), "add")
        XCTAssertNil(SourceNavigation.functionName(at: first.location + first.length, in: ranges))
        XCTAssertNil(SourceNavigation.functionName(at: -1, in: ranges))
    }

    func testVariableWordUnderTheCaretAndSelection() {
        let source = "int my_var2 = other + 10;\nreturn my_var2;\n"
        let ns = source as NSString
        let inside = ns.range(of: "my_var2").location + 3

        XCTAssertEqual(SourceNavigation.variableWord(at: inside, in: source, selection: NSRange(location: NSNotFound, length: 0)), "my_var2")
        // At the very end of a word the caret still belongs to it.
        XCTAssertEqual(SourceNavigation.variableWord(at: ns.range(of: "other").upperBound, in: source,
                                                     selection: NSRange(location: NSNotFound, length: 0)), "other")
        // Keywords are not variables.
        XCTAssertNil(SourceNavigation.variableWord(at: 1, in: source, selection: NSRange(location: NSNotFound, length: 0)))
        // A selected single word wins over the click position.
        let selection = ns.range(of: "other")
        XCTAssertEqual(SourceNavigation.variableWord(at: 0, in: source, selection: selection), "other")
        // The word never crosses a line break.
        let broken = "a +\nb" as NSString
        XCTAssertNil(SourceNavigation.variableWord(at: broken.range(of: "\n").location, in: broken as String, selection: NSRange(location: NSNotFound, length: 0)))
    }

    func testBodyRangeCoversTheFunctionBody() throws {
        let range = try XCTUnwrap(SourceNavigation.bodyRange(for: "add", source: cSource, fileExtension: "c"))
        let body = text(cSource, range)
        // The region spans the signature and the body, not just the braces.
        XCTAssertTrue(body.hasPrefix("int add"), body)
        XCTAssertTrue(body.contains("return a + b"))
        XCTAssertNil(SourceNavigation.bodyRange(for: "missing", source: cSource, fileExtension: "c"))
    }

    func testSnippetIsTheNamedRangeOrTheWholeSource() {
        let ranges = SourceNavigation.clickableRanges(source: cSource, fileExtension: "c").functions
        XCTAssertEqual(SourceNavigation.extractSnippet(for: "run", in: cSource, functionRanges: ranges), "run")
        XCTAssertEqual(SourceNavigation.extractSnippet(for: "absent", in: cSource, functionRanges: ranges), cSource)
    }

    func testLineStartsCountUTF16Units() {
        XCTAssertEqual(SourceNavigation.flowLineStarts(in: "a\nb\n"), [0, 2, 4])
        // An emoji is two UTF-16 units.
        XCTAssertEqual(SourceNavigation.flowLineStarts(in: "\u{1F600}\nx"), [0, 3])
        XCTAssertEqual(SourceNavigation.flowLineStarts(in: ""), [0])
    }

    func testFlowArrowsFollowBranchesAndLoops() {
        // One-line bodies produce no arrows (an arrow needs two different lines), so use a spread-out function.
        let source = """
            int run(int n) {
                int x = 0;
                if (n > 0) {
                    x = 1;
                } else {
                    x = 2;
                }
                while (x < 10) {
                    x = x + 1;
                }
                return x;
            }
            """
        let result = SourceNavigation.flowArrows(for: source, fileExtension: "c")
        let kinds = Set(result.arrows.map(\.kind))

        XCTAssertEqual(result.lineStarts.count, 12)
        XCTAssertTrue(kinds.contains(.branchTrue), "\(kinds)")
        XCTAssertTrue(kinds.contains(.branchFalse), "\(kinds)")
        XCTAssertTrue(kinds.contains(.loopBack), "\(kinds)")
        XCTAssertTrue(kinds.contains(.exit), "\(kinds)")
        for arrow in result.arrows {
            XCTAssertTrue((1...12).contains(arrow.fromLine) && (1...12).contains(arrow.toLine), "\(arrow)")
        }
        // Each arrow appears once.
        XCTAssertEqual(result.arrows.count, Set(result.arrows).count)
    }

    func testFlowArrowsForUnknownLanguageAreEmptyButLineStartsRemain() {
        let result = SourceNavigation.flowArrows(for: "a\nb", fileExtension: "txt")
        XCTAssertTrue(result.arrows.isEmpty)
        XCTAssertEqual(result.lineStarts, [0, 2])
    }

    func testFlowArrowKindEncodesAsItsName() throws {
        let data = try JSONEncoder().encode([FlowArrow.Kind.branchTrue, .loopBack])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["branchTrue","loopBack"]"#)
    }
}
