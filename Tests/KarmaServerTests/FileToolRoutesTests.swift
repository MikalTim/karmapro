// by cipher.org.uk
#if WebServer
import Foundation
import KarmaCore
import XCTVapor
@testable import KarmaServer

/// The source viewer, search, package, licence, notes and help routes, called on an app that holds only
/// those routes and the error middleware. HOME and XDG_DATA_HOME point at a throwaway folder before
/// `NoteStore.shared` is first used, so the notes tests never touch the real store.
final class FileToolRoutesTests: XCTestCase {
    private static var sandbox: URL?
    private var projects: [URL] = []

    override class func setUp() {
        super.setUp()
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-filetool-home-\(UUID().uuidString)", isDirectory: true)
        Self.sandbox = sandbox
        let previousHome = ProcessInfo.processInfo.environment["HOME"]
        let previousXDG = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        setenv("HOME", sandbox.path, 1)
        setenv("XDG_DATA_HOME", sandbox.appendingPathComponent("data").path, 1)
        _ = NotesService.list()
        restoreEnvironment("HOME", previousHome)
        restoreEnvironment("XDG_DATA_HOME", previousXDG)
    }

    override class func tearDown() {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        KarmaWorkspace.shared.close()
    }

    override func tearDown() {
        KarmaWorkspace.shared.close()
        for project in projects { try? FileManager.default.removeItem(at: project) }
        projects = []
        super.tearDown()
    }

    private static func restoreEnvironment(_ name: String, _ value: String?) {
        if let value { setenv(name, value, 1) } else { unsetenv(name) }
    }

    // MARK: - Helpers

    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        let api = app.grouped("api").grouped(KarmaErrorMiddleware())
        registerFileRoutes(api)
        registerToolRoutes(api)
        return app
    }

    /// A folder with the given files, removed when the test ends.
    private func makeProject(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-filetool-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        projects.append(root)
        return root
    }

    /// A query value with `&`, `=` and `+` escaped.
    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+")))
            ?? value
    }

    private func decode<T: Decodable>(_ type: T.Type, from body: ByteBuffer) throws -> T {
        try KarmaJSON.decoder.decode(T.self, from: Data(body.readableBytesView))
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try KarmaJSON.decoder.decode(T.self, from: data)
    }

    private func errorMessage(_ body: ByteBuffer) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: Data(body.readableBytesView)) as? [String: Any]
        return object?["error"] as? String
    }

    /// Polls the job until it leaves `running`, as a front end does through `GET /api/jobs/:id`.
    private func waitForJob(_ id: String, timeout: TimeInterval = 30) async throws -> JobDTO {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let job = KarmaJobCenter.shared.job(id), job.status != "running" {
                return job
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The job \(id) did not finish within \(timeout) seconds.")
        throw JobTimedOut()
    }

    private func jobId(_ body: ByteBuffer) throws -> String {
        struct Started: Decodable { let jobId: String }
        return try decode(Started.self, from: body).jobId
    }

    // MARK: - Source viewer

    func testFileRouteReturnsTokensAndTextWithUTF16Offsets() async throws {
        let root = try makeProject(["calc.c": "char *name = \"café\"; int count = 42;\n"])
        let path = root.appendingPathComponent("calc.c").path
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/file?path=\(escape(path))") { res async throws in
            XCTAssertEqual(res.status, .ok)
            let file = try self.decode(FileService.FileDTO.self, from: res.body)
            XCTAssertEqual(file.text, "char *name = \"café\"; int count = 42;\n")
            XCTAssertEqual(file.ext, "c")
            let forty = (file.text as NSString).range(of: "42").location
            XCTAssertTrue(file.tokens.contains { $0.kind == "number" && $0.location == forty && $0.length == 2 },
                          "the number token must sit at the UTF-16 offset after the accented letter")
            XCTAssertTrue(file.tokens.contains { $0.kind == "keyword" && $0.location == 0 && $0.length == 4 })
        }
    }

    func testFileRouteWithoutPathIsBadRequestJSON() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/file") { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertEqual(res.headers.contentType?.serialize().hasPrefix("application/json"), true)
            XCTAssertNotNil(try self.errorMessage(res.body))
        }
    }

    func testFileRouteForUnreadableFileIsBadRequest() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("karma-missing-\(UUID().uuidString).c").path
        try await app.test(.GET, "api/file?path=\(escape(missing))") { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertTrue(try self.errorMessage(res.body)?.hasPrefix("Could not read file") == true)
        }
    }

    func testFocusIsNullWithoutBodyAndContextMenuReadsItsQueryFlags() async throws {
        let root = try makeProject(["main.c": "int main(void) { return 0; }\n"])
        let path = escape(root.appendingPathComponent("main.c").path)
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/file/focus?path=\(path)&function=missing") { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(String(decoding: Data(res.body.readableBytesView), as: UTF8.self), "null")
        }
        try await app.test(.GET, "api/file/context-menu?path=\(path)&location=0&flowArrowsOn=0") { res async throws in
            XCTAssertEqual(res.status, .ok)
            let menu = try self.decode(FileService.ContextMenuDTO.self, from: res.body)
            XCTAssertFalse(menu.flowArrowsOn)
            XCTAssertEqual(menu.flowArrowsTitle, "Show Flow Arrows on Code")
        }
        try await app.test(.GET, "api/file/context-menu?path=\(path)&location=999") { res async throws in
            XCTAssertEqual(res.status, .badRequest, "an offset past the end of the file is refused")
        }
        try await app.test(.GET, "api/file/context-menu?path=\(path)&location=0&selectionLocation=5&selectionLength=-1") { res async throws in
            XCTAssertEqual(res.status, .badRequest, "a negative selection is refused")
        }
    }

    // MARK: - Line notes

    func testLineNoteRoutesNeedAnOpenProject() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        let path = escape("/tmp/karma-no-project.c")
        try await app.test(.GET, "api/notes/line?path=\(path)&line=1") { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertNotNil(try self.errorMessage(res.body))
        }
        try await app.test(.DELETE, "api/notes/line?path=\(path)&line=1") { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        }
        try await app.test(.PUT, "api/notes/line?path=\(path)&line=1", beforeRequest: { req in
            try req.content.encode(["text": "check"])
        }) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testLineNoteRoundTripShowsInFileNoteLines() async throws {
        let root = try makeProject(["notes.c": "int a;\nint b;\n"])
        _ = try ProjectService.open(path: root.path)
        let path = escape(root.appendingPathComponent("notes.c").path)
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        try await app.test(.PUT, "api/notes/line?path=\(path)&line=2", beforeRequest: { req in
            try req.content.encode(["text": "check"])
        }) { res async throws in
            XCTAssertEqual(res.status, .ok)
        }
        try await app.test(.GET, "api/notes/line?path=\(path)&line=2") { res async throws in
            XCTAssertEqual(res.status, .ok)
            let note = try self.decode(TextBody.self, from: res.body)
            XCTAssertEqual(note.text, "check")
        }
        try await app.test(.GET, "api/file?path=\(path)") { res async throws in
            let file = try self.decode(FileService.FileDTO.self, from: res.body)
            XCTAssertEqual(file.noteLines, [2])
        }
        try await app.test(.DELETE, "api/notes/line?path=\(path)&line=2") { res async throws in
            XCTAssertEqual(res.status, .ok)
        }
        try await app.test(.GET, "api/notes/line?path=\(path)&line=2") { res async throws in
            let note = try self.decode(TextBody.self, from: res.body)
            XCTAssertNil(note.text)
        }
    }

    // MARK: - Search

    func testSearchJobFindsEveryMatchingLine() async throws {
        let root = try makeProject(["search.c": "int Alpha = 1;\nint beta = 2;\n// alpha again\n"])
        _ = try ProjectService.open(path: root.path)
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        var id = ""
        try await app.test(.POST, "api/search", beforeRequest: { req in
            try req.content.encode(["term": "alpha"])
        }) { res async throws in
            XCTAssertEqual(res.status, .ok)
            id = try self.jobId(res.body)
        }
        let job = try await waitForJob(id)
        XCTAssertEqual(job.status, "completed")
        let result = try decode(SearchService.ResultDTO.self, from: job.resultJSON ?? Data())
        XCTAssertEqual(result.matches.map(\.line), [1, 3])
        XCTAssertEqual(result.statusText, "2 matches")
    }

    // MARK: - Packages and licences

    func testPackageDetectWithoutProjectIsBadRequest() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/packages/detect") { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertTrue(try self.errorMessage(res.body)?.contains("No Project Folder Open") == true)
        }
    }

    func testPackageStateIsListedAndExportWithoutFindingsIsRefused() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/packages") { res async throws in
            XCTAssertEqual(res.status, .ok)
            let state = try self.decode(PackageScanService.StateDTO.self, from: res.body)
            XCTAssertEqual(state.apiSources.count, 1)
            XCTAssertTrue(state.findings.isEmpty)
        }
        try await app.test(.GET, "api/packages/export") { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testLicenseJobCompletesWithAReport() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        var id = ""
        try await app.test(.POST, "api/licenses") { res async throws in
            XCTAssertEqual(res.status, .ok)
            id = try self.jobId(res.body)
        }
        let job = try await waitForJob(id)
        XCTAssertEqual(job.status, "completed")
        let report = try decode(LicenseService.ReportDTO.self, from: job.resultJSON ?? Data())
        XCTAssertFalse(report.report.isEmpty)
    }

    // MARK: - Notes

    func testNotesListAndExportReadTheSandboxStore() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/notes") { res async throws in
            XCTAssertEqual(res.status, .ok)
            let list = try self.decode(NotesService.ListDTO.self, from: res.body)
            XCTAssertNil(list.root)
        }
        try await app.test(.GET, "api/notes/export") { res async throws in
            XCTAssertEqual(res.status, .ok)
            let disposition = res.headers.first(name: .contentDisposition) ?? ""
            XCTAssertTrue(disposition.hasSuffix("-notes.codenotes\""), disposition)
        }
    }

    func testNotesImportRefusesAnEmptyBody() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/notes/import") { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertNotNil(try self.errorMessage(res.body))
        }
    }

    func testNotesImportURLRefusesAnInvalidAddress() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/notes/import-url", beforeRequest: { req in
            try req.content.encode(["url": "   "])
        }) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertEqual(try self.errorMessage(res.body), "Enter a valid web address.")
        }
    }

    // MARK: - Help

    func testHelpReturnsTheHelpPageAsHTML() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let previous = KarmaResources.directory
        KarmaResources.directory = repository.appendingPathComponent("Resources_src", isDirectory: true)
        defer { KarmaResources.directory = previous }
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/help") { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.headers.contentType?.serialize().hasPrefix("text/html"), true)
            XCTAssertTrue(String(decoding: Data(res.body.readableBytesView), as: UTF8.self).contains("<html"))
        }
    }
}

/// `{"text": <string or null>}`, as the line-note route answers.
private struct TextBody: Decodable {
    let text: String?
}

/// Thrown when a job is still running after the polling timeout.
private struct JobTimedOut: Error {}
#endif
