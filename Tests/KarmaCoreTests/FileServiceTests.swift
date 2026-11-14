import Foundation
import XCTest
@testable import KarmaCore

/// The source viewer's service: highlighting and clickable ranges, call sites, flow arrows,
/// focus chips, the context menu, definitions and line notes.
final class FileServiceTests: XCTestCase {

    /// The C fixture. `café 🙂` sits before `helper`, so UTF-16 offsets differ from Swift character offsets.
    private static let cSource = """
    #include <stdio.h>
    static const char *label = "café 🙂";
    int helper(int x) {
        return x + 1;
    }
    int main(void) {
        char buf[16];
        int y = helper(2);
        return y;
    }

    """

    /// The throwaway folder `NoteStore.shared` writes into; removed after the class.
    private static var noteSandbox: URL?

    /// Points `NoteStore.shared` at a throwaway folder. The store reads its folder once, on first use, so
    /// HOME and XDG_DATA_HOME are set only while it is first touched and restored straight after.
    override class func setUp() {
        super.setUp()
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-fileservice-home-\(UUID().uuidString)", isDirectory: true)
        noteSandbox = sandbox
        let previousHome = ProcessInfo.processInfo.environment["HOME"]
        let previousXDG = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        setenv("HOME", sandbox.path, 1)
        setenv("XDG_DATA_HOME", sandbox.appendingPathComponent("data").path, 1)
        _ = NoteStore.shared
        restoreEnvironment("HOME", previousHome)
        restoreEnvironment("XDG_DATA_HOME", previousXDG)
    }

    override class func tearDown() {
        if let noteSandbox { try? FileManager.default.removeItem(at: noteSandbox) }
        super.tearDown()
    }

    private static func restoreEnvironment(_ name: String, _ value: String?) {
        if let value { setenv(name, value, 1) } else { unsetenv(name) }
    }

    override func setUp() {
        super.setUp()
        KarmaWorkspace.shared.close()
    }

    override func tearDown() {
        KarmaWorkspace.shared.close()
        super.tearDown()
    }

    /// Polls until `condition` holds, so tests do not depend on how fast a background job runs.
    private func waitUntil(_ message: String, timeout: TimeInterval = 10, _ condition: () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for: \(message)", file: file, line: line)
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func makeProject(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-fileservice-\(UUID().uuidString)", isDirectory: true)
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    /// Opens a project and waits until its index is ready, so call sites and focus chips resolve.
    private func openReadyProject(_ files: [String: String]) throws -> URL {
        let root = try makeProject(files)
        try KarmaWorkspace.shared.open(root: root.path)
        waitUntil("the index is ready") { KarmaWorkspace.shared.info().indexState == "ready" }
        return root
    }

    /// The UTF-16 range of the first occurrence of `needle` in `text`.
    private func utf16Range(of needle: String, in text: String) -> NSRange {
        (text as NSString).range(of: needle)
    }

    private func substring(_ range: NSRange, of text: String) -> String {
        (text as NSString).substring(with: range)
    }

    // MARK: - File and tokens

    func testFileReturnsTokensWhoseKindsMatchTheTokenizer() throws {
        let root = try makeProject(["vuln.c": Self.cSource])
        let path = root.appendingPathComponent("vuln.c").path

        let dto = try FileService.file(path: path)

        XCTAssertEqual(dto.ext, "c")
        XCTAssertEqual(dto.text, Self.cSource)
        let keyword = dto.tokens.first { substring(NSRange(location: $0.location, length: $0.length), of: dto.text) == "char" }
        XCTAssertEqual(keyword?.kind, "keyword")
        let literal = dto.tokens.first { substring(NSRange(location: $0.location, length: $0.length), of: dto.text) == "\"café 🙂\"" }
        XCTAssertEqual(literal?.kind, "string", "a string with multi-byte text must keep its UTF-16 span")
    }

    func testFunctionRangesAreUTF16OffsetsIntoTheText() throws {
        let root = try makeProject(["vuln.c": Self.cSource])
        let path = root.appendingPathComponent("vuln.c").path

        let dto = try FileService.file(path: path)

        XCTAssertEqual(dto.functionRanges.map(\.name), ["helper", "main"])
        let helper = try XCTUnwrap(dto.functionRanges.first)
        XCTAssertEqual(substring(NSRange(location: helper.location, length: helper.length), of: dto.text), "helper")
        XCTAssertEqual(helper.location, utf16Range(of: "helper(int", in: dto.text).location)
        // Swift character offsets and UTF-16 offsets differ here, so the test fails if the service mixes them up.
        let characterOffset = Self.cSource.distance(from: Self.cSource.startIndex,
                                                    to: Self.cSource.range(of: "helper(int")!.lowerBound)
        XCTAssertNotEqual(characterOffset, helper.location)
    }

    func testClassRangesAreReturnedForJava() throws {
        let root = try makeProject(["Greeter.java": "public class Greeter {\n    void run() {}\n}\n"])
        let path = root.appendingPathComponent("Greeter.java").path

        let dto = try FileService.file(path: path)

        let cls = try XCTUnwrap(dto.classRanges.first)
        XCTAssertEqual(cls.name, "Greeter")
        XCTAssertEqual(substring(NSRange(location: cls.location, length: cls.length), of: dto.text), "Greeter")
    }

    func testUnreadableFileThrowsTheViewerMessage() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-missing-\(UUID().uuidString).c").path

        XCTAssertThrowsError(try FileService.file(path: missing)) { error in
            guard case KarmaServiceError.invalid(let message) = error else {
                return XCTFail("expected invalid, got \(error)")
            }
            XCTAssertEqual(message, "Could not read file:\n\(missing)")
        }
    }

    // MARK: - Call sites

    func testCallSitesAppearOnlyOnceTheProjectIndexIsReady() throws {
        let root = try makeProject(["vuln.c": Self.cSource])
        let path = root.appendingPathComponent("vuln.c").path

        XCTAssertTrue(try FileService.file(path: path).callSites.isEmpty,
                      "no call sites before a project is indexed")

        try KarmaWorkspace.shared.open(root: root.path)
        waitUntil("the index is ready") { KarmaWorkspace.shared.info().indexState == "ready" }

        let dto = try FileService.file(path: path)
        XCTAssertEqual(dto.callSites.map(\.name), ["helper"], "the definition of main and the call to helper")
        let site = try XCTUnwrap(dto.callSites.first)
        XCTAssertEqual(site.location, utf16Range(of: "helper(2)", in: dto.text).location)
    }

    func testResolveCallReturnsTheDefinitionTextAndLine() throws {
        let root = try openReadyProject(["vuln.c": Self.cSource])
        let path = root.appendingPathComponent("vuln.c").path

        let definition = try XCTUnwrap(try FileService.resolveCall(path: path, name: "helper"))

        XCTAssertEqual(definition.path, path)
        XCTAssertEqual(definition.name, "helper")
        XCTAssertEqual(definition.text, Self.cSource)
        XCTAssertEqual(definition.line, 3, "helper is defined on line 3 of the fixture")
        XCTAssertNil(try FileService.resolveCall(path: path, name: "doesNotExist"))
    }

    func testDefinitionUsesTheLineOfTheNameOffset() throws {
        let root = try makeProject(["vuln.c": Self.cSource])
        let path = root.appendingPathComponent("vuln.c").path
        let offset = utf16Range(of: "main(void)", in: Self.cSource).location

        let definition = try FileService.definition(path: path, nameOffset: offset)

        XCTAssertEqual(definition.line, 6)
        XCTAssertEqual(definition.name, "main")
    }

    // MARK: - Flow arrows

    func testFlowArrowsDescribeBranchesAndExits() throws {
        let source = """
        int classify(int x) {
            if (x > 0) {
                return 1;
            }
            return 0;
        }

        """
        let root = try makeProject(["flow.c": source])

        let dto = try FileService.flowArrows(path: root.appendingPathComponent("flow.c").path)

        XCTAssertEqual(dto.lineStarts.first, 0)
        XCTAssertEqual(dto.lineStarts.count, 7, "one start per line, including the empty last line")
        XCTAssertEqual(dto.lineStarts[1], utf16Range(of: "if (x", in: source).location - 4)
        XCTAssertTrue(dto.arrows.contains { $0.kind == "branchTrue" && $0.fromLine == 2 }, "the decision on line 2 branches true")
        XCTAssertTrue(dto.arrows.contains { $0.kind == "exit" && $0.fromLine == 3 }, "return on line 3 exits")
    }

    // MARK: - Focus

    func testFocusListsCallersAndCalleesWithTheirFiles() throws {
        let root = try openReadyProject(["vuln.c": Self.cSource])
        let path = root.appendingPathComponent("vuln.c").path

        let onMain = try XCTUnwrap(try FileService.focus(path: path, function: "main"))
        XCTAssertEqual(onMain.callees.map(\.name), ["helper"])
        XCTAssertEqual(onMain.callees.first?.path, path)
        XCTAssertTrue(onMain.callers.isEmpty)
        XCTAssertGreaterThan(onMain.bodyLength, 0)

        let onHelper = try XCTUnwrap(try FileService.focus(path: path, function: "helper"))
        XCTAssertEqual(onHelper.callers.map(\.name), ["main"])
        XCTAssertTrue(onHelper.callees.isEmpty)

        XCTAssertNil(try FileService.focus(path: path, function: "notInThisFile"),
                     "a function without a body in the file does not enter focus mode")
    }

    // MARK: - Context menu

    func testContextMenuFollowsThePointerAndTheSelection() throws {
        let root = try openReadyProject(["vuln.c": Self.cSource])
        let path = root.appendingPathComponent("vuln.c").path
        let nameLocation = utf16Range(of: "helper(int", in: Self.cSource).location + 2

        let onName = try FileService.contextMenu(path: path, location: nameLocation,
                                                 selectionLocation: 0, selectionLength: 0)
        XCTAssertEqual(onName.functionName, "helper")
        XCTAssertEqual(onName.variableName, "helper")
        XCTAssertTrue(onName.flowDiagramSupported)
        XCTAssertTrue(onName.copyEnabled)
        XCTAssertEqual(onName.flowArrowsTitle, "Hide Flow Arrows on Code")
        XCTAssertFalse(onName.exitFocusAvailable)
        XCTAssertEqual(onName.lineNumber, 3)
        XCTAssertEqual(onName.lineText, "int helper(int x) {")
        XCTAssertEqual(onName.variableFlowLocation, nameLocation)

        let onWhitespace = try FileService.contextMenu(path: path, location: 0,
                                                       selectionLocation: 0, selectionLength: 0,
                                                       flowArrowsOn: false, focusActive: true)
        XCTAssertNil(onWhitespace.functionName)
        XCTAssertEqual(onWhitespace.flowArrowsTitle, "Show Flow Arrows on Code")
        XCTAssertTrue(onWhitespace.exitFocusAvailable)
    }

    func testVariableFlowAnchorsAtTheSelectionStartWhenClickedInsideIt() throws {
        let root = try openReadyProject(["vuln.c": Self.cSource])
        let path = root.appendingPathComponent("vuln.c").path
        let selectionStart = utf16Range(of: "buf[16]", in: Self.cSource).location
        let click = selectionStart + 2

        let menu = try FileService.contextMenu(path: path, location: click,
                                               selectionLocation: selectionStart, selectionLength: 7)

        XCTAssertEqual(menu.variableFlowLocation, selectionStart)
    }

    // MARK: - Line notes

    func testLineNotesAreSavedReadAndDeleted() throws {
        let root = try openReadyProject(["vuln.c": Self.cSource])
        let path = root.appendingPathComponent("vuln.c").path

        XCTAssertNil(try FileService.lineNote(path: path, line: 4))
        try FileService.saveLineNote(path: path, line: 4, text: "  check this  ")

        XCTAssertEqual(try FileService.lineNote(path: path, line: 4), "check this")
        XCTAssertEqual(try FileService.file(path: path).noteLines, [4])

        try FileService.deleteLineNote(path: path, line: 4)

        XCTAssertNil(try FileService.lineNote(path: path, line: 4))
        XCTAssertEqual(try FileService.file(path: path).noteLines, [])
    }

    func testBlankNoteTextRemovesTheNote() throws {
        let root = try openReadyProject(["vuln.c": Self.cSource])
        let path = root.appendingPathComponent("vuln.c").path

        try FileService.saveLineNote(path: path, line: 5, text: "keep me")
        try FileService.saveLineNote(path: path, line: 5, text: "   ")

        XCTAssertNil(try FileService.lineNote(path: path, line: 5))
    }

    func testLineNotesNeedAnOpenProject() throws {
        let root = try makeProject(["vuln.c": Self.cSource])
        let path = root.appendingPathComponent("vuln.c").path

        XCTAssertThrowsError(try FileService.saveLineNote(path: path, line: 1, text: "x")) { error in
            guard case KarmaServiceError.noProject = error else {
                return XCTFail("expected noProject, got \(error)")
            }
        }
    }
}
