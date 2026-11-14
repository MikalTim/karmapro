// by cipher.org.uk
#if WebServer
import Foundation
import XCTVapor
@testable import KarmaCore
@testable import KarmaServer

/// The bug and wiki routes as a front end calls them. The services write to a temporary store
/// (`storeOverride`), never to the real home or Application Support folder. Archive tests are
/// skipped when `zip` and `unzip` are not installed.
final class BugWikiRoutesTests: XCTestCase {

    override func tearDown() {
        BugService.storeOverride = nil
        WikiService.storeOverride = nil
        WikiService.clock = { Date() }
        super.tearDown()
    }

    // MARK: - Helpers

    private struct Reply {
        let status: HTTPStatus
        let headers: HTTPHeaders
        let body: Data
    }

    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        let api = app.grouped("api").grouped(KarmaErrorMiddleware())
        registerBugRoutes(api)
        registerWikiRoutes(api)
        return app
    }

    private func send(_ app: Application, _ method: HTTPMethod, _ path: String, body: Data? = nil,
                      contentType: String = "application/json") async throws -> Reply {
        var reply: Reply?
        try await app.test(method, path,
                           headers: ["X-Karma-Client": "web", "Content-Type": contentType],
                           body: body.map { ByteBuffer(data: $0) }) { res async in
            reply = Reply(status: res.status, headers: res.headers, body: Data(res.body.readableBytesView))
        }
        return try XCTUnwrap(reply)
    }

    private func json<T: Encodable>(_ value: T) -> Data {
        KarmaJSON.data(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ reply: Reply) throws -> T {
        try KarmaJSON.decoder.decode(T.self, from: reply.body)
    }

    private func jsonObject(_ reply: Reply) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: reply.body) as? [String: Any])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-bugwiki-routes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// `BugStore` has no directory parameter, so it is built while `HOME` points at a temporary folder
    /// (its application support path follows `HOME`). The test is skipped when the platform does not
    /// place that folder under `HOME`, rather than writing to the real one.
    private func makeIsolatedBugStore() throws {
        let home = try temporaryDirectory()
        let previous = ProcessInfo.processInfo.environment["HOME"]
        setenv("HOME", home.path, 1)
        defer {
            if let previous { setenv("HOME", previous, 1) } else { unsetenv("HOME") }
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        try XCTSkipUnless(support?.path.hasPrefix(home.path) == true,
                          "The application support folder does not follow HOME on this platform.")
        BugService.storeOverride = BugStore()
    }

    private func makeIsolatedWiki() throws {
        WikiService.storeOverride = WikiStore(directory: try temporaryDirectory())
    }

    private func requireZipTools() throws {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = path.split(separator: ":").map(String.init)
        func installed(_ tool: String) -> Bool {
            directories.contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + tool) }
        }
        try XCTSkipUnless(installed("zip") && installed("unzip"),
                          "The zip and unzip tools are needed for wiki archives; this machine does not have both.")
    }

    private func bugInput(title: String, severity: String = "medium", status: String = "Open") -> BugService.BugInputDTO {
        BugService.BugInputDTO(title: title, severity: severity, exploitability: "low", detail: "",
                               packageName: "", version: "", status: status)
    }

    /// Every run style the editor can produce, plus a `wiki://` link.
    private func sampleDocument() -> WikiDocument {
        WikiDocument(paragraphs: [
            WikiParagraph(runs: [WikiRun(text: "Heading", bold: true, heading: true)]),
            WikiParagraph(runs: [
                WikiRun(text: "bold", bold: true),
                WikiRun(text: " italic", italic: true),
                WikiRun(text: " under", underline: true),
                WikiRun(text: " code", code: true),
                WikiRun(text: " see "),
                WikiRun(text: "Beta", link: "wiki://page/Beta"),
            ]),
        ])
    }

    private struct SaveBody: Encodable {
        let title: String
        let document: WikiDocument
    }

    // MARK: - Bug reports

    func testBugCreateListUpdateDeleteRoundTrip() async throws {
        try makeIsolatedBugStore()
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let created = try await send(app, .POST, "api/bugs", body: json(bugInput(title: "Overflow in parser")))
        XCTAssertEqual(created.status, .ok)
        let bug = try decode(BugService.BugDTO.self, created)
        XCTAssertEqual(bug.title, "Overflow in parser")
        XCTAssertEqual(bug.status, "Open")
        XCTAssertEqual(bug.shortID, String(bug.id.prefix(8)))

        let list = try decode(BugService.BugListDTO.self, try await send(app, .GET, "api/bugs?query=Overflow"))
        XCTAssertEqual(list.bugs.map(\.id), [bug.id])
        XCTAssertEqual(list.openCount, 1)
        XCTAssertEqual(list.countText, "1 bug")

        let updated = try await send(app, .PUT, "api/bugs/\(bug.id)",
                                     body: json(bugInput(title: "Overflow in parser", status: "Resolved")))
        XCTAssertEqual(updated.status, .ok)
        XCTAssertEqual(try decode(BugService.BugDTO.self, updated).status, "Resolved")
        let afterUpdate = try decode(BugService.BugListDTO.self, try await send(app, .GET, "api/bugs"))
        XCTAssertEqual(afterUpdate.openCount, 0)

        let deleted = try await send(app, .DELETE, "api/bugs/\(bug.id)")
        XCTAssertEqual(deleted.status, .ok)
        XCTAssertEqual(try jsonObject(deleted)["ok"] as? Bool, true)
        let remaining = try decode(BugService.BugListDTO.self, try await send(app, .GET, "api/bugs"))
        XCTAssertTrue(remaining.bugs.isEmpty)

        let missing = try await send(app, .DELETE, "api/bugs/\(bug.id)")
        XCTAssertEqual(missing.status, .notFound)
    }

    func testInvalidBugIsBadRequest() async throws {
        try makeIsolatedBugStore()
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let blank = try await send(app, .POST, "api/bugs", body: json(bugInput(title: "   ")))
        XCTAssertEqual(blank.status, .badRequest)
        XCTAssertEqual(try jsonObject(blank)["error"] as? String, "A title is required.")

        let severity = try await send(app, .POST, "api/bugs", body: json(bugInput(title: "T", severity: "extreme")))
        XCTAssertEqual(severity.status, .badRequest)
        XCTAssertEqual(try jsonObject(severity)["error"] as? String, "Unknown severity \"extreme\".")

        let malformed = try await send(app, .POST, "api/bugs", body: Data("{\"title\":1}".utf8))
        XCTAssertEqual(malformed.status, .badRequest)
    }

    func testChoicesCarryTheEditorListsAndDefaults() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let reply = try await send(app, .GET, "api/bugs/choices")
        XCTAssertEqual(reply.status, .ok)
        let choices = try decode(BugService.BugChoicesDTO.self, reply)
        XCTAssertTrue(choices.severities.contains("critical"))
        XCTAssertTrue(choices.statuses.contains("In Progress"))
        XCTAssertFalse(choices.presets.isEmpty)
        XCTAssertEqual(choices.defaults.severity, "info")
        XCTAssertEqual(choices.defaults.status, "Open")
    }

    func testEncryptedBugBackupNeedsItsPasswordAndRestores() async throws {
        try makeIsolatedBugStore()
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let created = try decode(BugService.BugDTO.self,
                                 try await send(app, .POST, "api/bugs", body: json(bugInput(title: "Kept"))))

        let backup = try await send(app, .POST, "api/bugs/backup", body: json(["password": "s3cret"]))
        XCTAssertEqual(backup.status, .ok)
        XCTAssertEqual(backup.headers.first(name: .contentDisposition),
                       "attachment; filename=\"KarmaProBugBackup.karmapro\"")
        XCTAssertTrue(BackupCrypto.isEncrypted(backup.body))

        let removed = try await send(app, .DELETE, "api/bugs/\(created.id)")
        XCTAssertEqual(removed.status, .ok)

        let refused = try await send(app, .POST, "api/bugs/import?filename=b.karmapro", body: backup.body,
                                     contentType: "application/octet-stream")
        XCTAssertEqual(refused.status, .unprocessableEntity)
        let refusedObject = try jsonObject(refused)
        XCTAssertEqual(refusedObject["needsPassword"] as? Bool, true)
        XCTAssertNotNil(refusedObject["error"] as? String)

        let wrong = try await send(app, .POST, "api/bugs/import?password=nope", body: backup.body,
                                   contentType: "application/octet-stream")
        XCTAssertEqual(wrong.status, .badRequest)
        XCTAssertNotNil(try jsonObject(wrong)["error"] as? String)

        let restored = try await send(app, .POST, "api/bugs/import?password=s3cret", body: backup.body,
                                      contentType: "application/octet-stream")
        XCTAssertEqual(restored.status, .ok)
        let result = try decode(BugService.BugImportResultDTO.self, restored)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.found, 1)
        XCTAssertTrue(result.encrypted)
        let list = try decode(BugService.BugListDTO.self, try await send(app, .GET, "api/bugs"))
        XCTAssertEqual(list.bugs.map(\.title), ["Kept"])
    }

    func testPlainBugBackupRoundTripAndBadUploads() async throws {
        try makeIsolatedBugStore()
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let created = try decode(BugService.BugDTO.self,
                                 try await send(app, .POST, "api/bugs", body: json(bugInput(title: "Plain"))))
        let backup = try await send(app, .POST, "api/bugs/backup")
        XCTAssertEqual(backup.status, .ok)
        XCTAssertFalse(BackupCrypto.isEncrypted(backup.body))

        let removed = try await send(app, .DELETE, "api/bugs/\(created.id)")
        XCTAssertEqual(removed.status, .ok)
        let restored = try await send(app, .POST, "api/bugs/import", body: backup.body,
                                      contentType: "application/octet-stream")
        XCTAssertEqual(try decode(BugService.BugImportResultDTO.self, restored).added, 1)

        let garbage = try await send(app, .POST, "api/bugs/import", body: Data("not a backup".utf8),
                                     contentType: "application/octet-stream")
        XCTAssertEqual(garbage.status, .badRequest)
        XCTAssertNotNil(try jsonObject(garbage)["error"] as? String)

        let empty = try await send(app, .POST, "api/bugs/import", contentType: "application/octet-stream")
        XCTAssertEqual(empty.status, .badRequest)

        let blankPassword = try await send(app, .POST, "api/bugs/backup", body: json(["password": ""]))
        XCTAssertEqual(blankPassword.status, .badRequest)
    }

    // MARK: - Wiki pages

    func testWikiPageCreateSaveRenameAndDelete() async throws {
        try makeIsolatedWiki()
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let page = try decode(WikiService.WikiPageDTO.self,
                              try await send(app, .POST, "api/wiki", body: json(["title": "Alpha"])))
        XCTAssertEqual(page.slug, "alpha")

        let document = sampleDocument()
        let saved = try await send(app, .PUT, "api/wiki/alpha", body: json(SaveBody(title: "Alpha", document: document)))
        XCTAssertEqual(saved.status, .ok)

        let detail = try decode(WikiService.WikiPageDetailDTO.self, try await send(app, .GET, "api/wiki/alpha"))
        XCTAssertEqual(detail.info.title, "Alpha")
        XCTAssertEqual(detail.document, document)

        let renamed = try decode(WikiService.WikiPageDTO.self,
                                 try await send(app, .POST, "api/wiki/alpha/rename", body: json(["title": "Gamma"])))
        XCTAssertEqual(renamed.slug, "gamma")
        let old = try await send(app, .GET, "api/wiki/alpha")
        XCTAssertEqual(old.status, .notFound)

        let kept = try decode(WikiService.WikiPageDetailDTO.self, try await send(app, .GET, "api/wiki/gamma"))
        XCTAssertEqual(kept.document, document)

        let list = try decode(WikiService.WikiListDTO.self, try await send(app, .GET, "api/wiki?query=Gamma"))
        XCTAssertEqual(list.pages.map(\.slug), ["gamma"])
        XCTAssertEqual(list.statusText, "1 page matching \"Gamma\"")

        let deleted = try await send(app, .DELETE, "api/wiki/gamma")
        XCTAssertEqual(deleted.status, .ok)
        let gone = try await send(app, .GET, "api/wiki/gamma")
        XCTAssertEqual(gone.status, .notFound)
        let deletedAgain = try await send(app, .DELETE, "api/wiki/gamma")
        XCTAssertEqual(deletedAgain.status, .notFound)
    }

    func testResolveIsNotReadAsAPageSlug() async throws {
        try makeIsolatedWiki()
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        _ = try await send(app, .POST, "api/wiki", body: json(["title": "Alpha"]))

        let found = try await send(app, .GET, "api/wiki/resolve?target=Alpha")
        XCTAssertEqual(found.status, .ok)
        XCTAssertEqual(try jsonObject(found)["slug"] as? String, "alpha")

        let missing = try await send(app, .GET, "api/wiki/resolve?target=Missing")
        XCTAssertEqual(missing.status, .ok)
        XCTAssertTrue(try XCTUnwrap(jsonObject(missing)["slug"]) is NSNull)

        let noTarget = try await send(app, .GET, "api/wiki/resolve")
        XCTAssertEqual(noTarget.status, .badRequest)
    }

    func testMissingPageAndDuplicateSlugAreRefused() async throws {
        try makeIsolatedWiki()
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let missing = try await send(app, .GET, "api/wiki/nope")
        XCTAssertEqual(missing.status, .notFound)
        XCTAssertEqual(try jsonObject(missing)["error"] as? String, "The page no longer exists.")

        _ = try await send(app, .POST, "api/wiki", body: json(["title": "Alpha"]))
        let duplicate = try await send(app, .POST, "api/wiki", body: json(["title": "Other", "slug": "alpha"]))
        XCTAssertEqual(duplicate.status, .badRequest)
        XCTAssertEqual(try jsonObject(duplicate)["error"] as? String, "A page with that name already exists.")
    }

    // MARK: - Wiki backup and import

    func testWikiBackupAndImportRejectBlankAndBadUploads() async throws {
        try makeIsolatedWiki()
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let blankPassword = try await send(app, .POST, "api/wiki/backup", body: json(["password": ""]))
        XCTAssertEqual(blankPassword.status, .badRequest)

        let empty = try await send(app, .POST, "api/wiki/import", contentType: "application/octet-stream")
        XCTAssertEqual(empty.status, .badRequest)

        let garbage = try await send(app, .POST, "api/wiki/import?filename=x.karmawiki",
                                     body: Data("not an archive".utf8), contentType: "application/octet-stream")
        XCTAssertEqual(garbage.status, .badRequest)
        XCTAssertNotNil(try jsonObject(garbage)["error"] as? String)
    }

    func testEncryptedWikiUploadNeedsItsPassword() async throws {
        try makeIsolatedWiki()
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let sealed = try BackupCrypto.seal(Data("{}".utf8), password: "pw")

        let refused = try await send(app, .POST, "api/wiki/import", body: sealed,
                                     contentType: "application/octet-stream")
        XCTAssertEqual(refused.status, .unprocessableEntity)
        XCTAssertEqual(try jsonObject(refused)["needsPassword"] as? Bool, true)

        let wrong = try await send(app, .POST, "api/wiki/import?password=nope", body: sealed,
                                   contentType: "application/octet-stream")
        XCTAssertEqual(wrong.status, .badRequest)
    }

    func testUnknownImportIsNotFound() async throws {
        try makeIsolatedWiki()
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let reply = try await send(app, .POST, "api/wiki/import/unknown-id/resolve", body: json(["decisions": [String: String]()]))
        XCTAssertEqual(reply.status, .notFound)
        XCTAssertEqual(try jsonObject(reply)["error"] as? String, "The import expired; upload the file again.")
    }

    func testWikiArchiveBackupAndImportWithConflictAnswers() async throws {
        try requireZipTools()
        try makeIsolatedWiki()
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        _ = try await send(app, .POST, "api/wiki", body: json(["title": "Alpha"]))
        _ = try await send(app, .PUT, "api/wiki/alpha", body: json(SaveBody(title: "Alpha", document: sampleDocument())))

        let backup = try await send(app, .POST, "api/wiki/backup")
        XCTAssertEqual(backup.status, .ok)
        XCTAssertEqual(backup.headers.first(name: .contentDisposition),
                       "attachment; filename=\"KarmaProWiki.karmawiki\"")

        let encrypted = try await send(app, .POST, "api/wiki/backup", body: json(["password": "pw"]))
        XCTAssertEqual(encrypted.status, .ok)
        let needsPassword = try await send(app, .POST, "api/wiki/import", body: encrypted.body,
                                           contentType: "application/octet-stream")
        XCTAssertEqual(needsPassword.status, .unprocessableEntity)

        let removedAlpha = try await send(app, .DELETE, "api/wiki/alpha")
        XCTAssertEqual(removedAlpha.status, .ok)
        let first = try decode(WikiService.WikiImportSessionDTO.self,
                               try await send(app, .POST, "api/wiki/import?filename=a.karmawiki", body: backup.body,
                                              contentType: "application/octet-stream"))
        XCTAssertEqual(first.conflicts, [])
        let imported = try decode(WikiService.WikiImportResultDTO.self,
                                  try await send(app, .POST, "api/wiki/import/\(first.importID)/resolve",
                                                 body: json(["decisions": [String: String]()])))
        XCTAssertEqual(imported.imported, 1)
        let restored = try decode(WikiService.WikiPageDetailDTO.self, try await send(app, .GET, "api/wiki/alpha"))
        XCTAssertEqual(restored.document, sampleDocument())

        let second = try decode(WikiService.WikiImportSessionDTO.self,
                                try await send(app, .POST, "api/wiki/import?filename=a.karmawiki", body: backup.body,
                                               contentType: "application/octet-stream"))
        XCTAssertEqual(second.conflicts, ["alpha"])
        XCTAssertEqual(second.conflictTitles["alpha"], "Alpha")
        let overwritten = try decode(WikiService.WikiImportResultDTO.self,
                                     try await send(app, .POST, "api/wiki/import/\(second.importID)/resolve",
                                                    body: json(["decisions": ["alpha": "overwrite"]])))
        XCTAssertEqual(overwritten.overwritten, 1)
        XCTAssertEqual(overwritten.summary, "Imported: 1 overwritten.")
    }
}
#endif
