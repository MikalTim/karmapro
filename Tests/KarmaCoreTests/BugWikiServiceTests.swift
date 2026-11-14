import Foundation
import XCTest
@testable import KarmaCore

/// The bug tracker and wiki services as the front ends call them: reports and
/// pages are created, edited, backed up and imported, and the rules the windows
/// apply (validation, search, conflict answers, link targets) are checked.
final class BugWikiServiceTests: XCTestCase {

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-bugwiki-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// `BugStore` has no directory parameter, so the store is built while `HOME`
    /// points at a temporary folder (its application support path follows `HOME`).
    /// Only that instance is used; the shared store is never touched. When the
    /// platform does not place the support folder under `HOME`, the test is skipped
    /// rather than writing to the real folder.
    private func makeIsolatedBugStore() throws -> BugStore {
        let home = try temporaryDirectory()
        let previous = ProcessInfo.processInfo.environment["HOME"]
        setenv("HOME", home.path, 1)
        defer {
            if let previous { setenv("HOME", previous, 1) } else { unsetenv("HOME") }
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        try XCTSkipUnless(support?.path.hasPrefix(home.path) == true,
                          "The application support folder does not follow HOME on this platform.")
        let store = BugStore()
        BugService.storeOverride = store
        addTeardownBlock { BugService.storeOverride = nil }
        return store
    }

    private func bugInput(title: String, severity: String = "medium", status: String = "Open",
                          package: String = "", version: String = "", detail: String = "") -> BugService.BugInputDTO {
        BugService.BugInputDTO(title: title, severity: severity, exploitability: "low", detail: detail,
                               packageName: package, version: version, status: status)
    }

    private func requireZipTools() throws {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = path.split(separator: ":").map(String.init)
        func installed(_ tool: String) -> Bool {
            directories.contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + tool) }
        }
        try XCTSkipUnless(installed("zip") && installed("unzip"),
                          "The zip and unzip tools are needed for wiki backups; this machine does not have both.")
    }

    // MARK: - Bug reports

    func testCreateListFilterUpdateAndDeleteRoundTrip() throws {
        _ = try makeIsolatedBugStore()

        let first = try BugService.create(bugInput(title: "  Heap overflow in parser  ", severity: "high",
                                                   package: " libparse ", version: "2.1"))
        XCTAssertEqual(first.title, "Heap overflow in parser")
        XCTAssertEqual(first.packageName, "libparse")
        XCTAssertEqual(first.packageText, "libparse v2.1")
        XCTAssertEqual(first.shortID, String(first.id.prefix(8)))
        XCTAssertNil(first.filePath)

        let second = try BugService.create(bugInput(title: "Weak TLS config", severity: "low", status: "Resolved"))
        XCTAssertEqual(second.packageText, "—", "A report without a package shows a dash")

        let all = BugService.list(query: "")
        XCTAssertEqual(Set(all.bugs.map(\.title)), ["Heap overflow in parser", "Weak TLS config"])
        XCTAssertEqual(all.countText, "2 bugs")
        XCTAssertEqual(all.openCount, 1, "Only the open report counts")
        XCTAssertEqual(all.columns.map(\.id), ["id", "title", "severity", "exploitability", "package", "status", "created"])

        let byPackage = BugService.list(query: "LIBPARSE")
        XCTAssertEqual(byPackage.bugs.map(\.title), ["Heap overflow in parser"])
        XCTAssertEqual(byPackage.countText, "1 bug")

        let updated = try BugService.update(id: first.id, bugInput(title: "Heap overflow in parser",
                                                                   severity: "critical", status: "Closed",
                                                                   package: "libparse", version: "2.2",
                                                                   detail: "Reproduced with a crafted file"))
        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(updated.createdAt, first.createdAt, "The creation time is kept on update")
        XCTAssertEqual(updated.severity, "critical")
        XCTAssertEqual(updated.detail, "Reproduced with a crafted file")
        XCTAssertEqual(BugService.list(query: "").openCount, 0, "A closed report is not open")

        _ = try BugService.update(id: first.id, bugInput(title: "Heap overflow in parser", status: "In Progress"))
        XCTAssertEqual(BugService.list(query: "").openCount, 1, "In Progress counts as open")

        try BugService.delete(id: second.id)
        XCTAssertEqual(BugService.list(query: "").bugs.map(\.title), ["Heap overflow in parser"])
        XCTAssertThrowsError(try BugService.get(id: second.id)) { error in
            XCTAssertEqual((error as? KarmaServiceError)?.errorDescription, "The bug report no longer exists.")
        }
    }

    func testCreateRejectsABlankTitleAndUnknownChoices() throws {
        _ = try makeIsolatedBugStore()

        XCTAssertThrowsError(try BugService.create(bugInput(title: "   "))) { error in
            XCTAssertEqual((error as? KarmaServiceError)?.errorDescription, "A title is required.")
        }
        XCTAssertThrowsError(try BugService.create(bugInput(title: "X", severity: "severe"))) { error in
            XCTAssertEqual((error as? KarmaServiceError)?.errorDescription, "Unknown severity \"severe\".")
        }
        XCTAssertThrowsError(try BugService.create(bugInput(title: "X", status: "Done")))
        XCTAssertEqual(BugService.list(query: "").bugs.count, 0)
    }

    func testChoicesCarryTheEditorListsAndDefaults() {
        let choices = BugService.choices()

        XCTAssertEqual(choices.severities, ["info", "low", "medium", "high", "critical"])
        XCTAssertEqual(choices.statuses, ["Open", "In Progress", "Resolved", "Closed"])
        XCTAssertEqual(choices.defaults.severity, "info", "The editor's first popup item is the default")
        XCTAssertEqual(choices.defaults.exploitability, "info")
        XCTAssertEqual(choices.defaults.status, "Open")
        XCTAssertEqual(choices.presets.first?.title, "SQL Injection")
        XCTAssertTrue(choices.presets.first?.description?.hasPrefix("User-supplied data") == true)
        XCTAssertGreaterThan(choices.presets.count, 400)
    }

    func testBackupWithPasswordNeedsThePasswordToImport() throws {
        let store = try makeIsolatedBugStore()
        let report = try BugService.create(bugInput(title: "Secret report"))

        let protected = try BugService.backup(password: "hunter2")
        XCTAssertEqual(protected.fileName, "KarmaProBugBackup.karmapro")
        XCTAssertTrue(BackupCrypto.isEncrypted(protected.data))

        try BugService.delete(id: report.id)
        XCTAssertEqual(store.allBugs().count, 0)

        XCTAssertThrowsError(try BugService.importBackup(data: protected.data, password: nil)) { error in
            guard case BugService.ImportError.needsPassword = error else {
                return XCTFail("Expected needsPassword, got \(error)")
            }
        }
        XCTAssertThrowsError(try BugService.importBackup(data: protected.data, password: "wrong")) { error in
            guard case BugService.ImportError.wrongPassword = error else {
                return XCTFail("Expected wrongPassword, got \(error)")
            }
            XCTAssertEqual(error.localizedDescription, "The password is incorrect.")
        }

        let restored = try BugService.importBackup(data: protected.data, password: "hunter2")
        XCTAssertEqual(restored.found, 1)
        XCTAssertEqual(restored.added, 1)
        XCTAssertTrue(restored.encrypted)
        XCTAssertEqual(BugService.list(query: "").bugs.map(\.title), ["Secret report"])

        let again = try BugService.importBackup(data: protected.data, password: "hunter2")
        XCTAssertEqual(again.added, 0, "Reports whose ids already exist are not added twice")
    }

    func testPlainBackupRoundTripAndBlankPassword() throws {
        _ = try makeIsolatedBugStore()
        let report = try BugService.create(bugInput(title: "Plain report"))

        XCTAssertThrowsError(try BugService.backup(password: "")) { error in
            XCTAssertEqual((error as? KarmaServiceError)?.errorDescription,
                           "The passwords did not match or were blank. No backup was saved.")
        }

        let plain = try BugService.backup(password: nil)
        XCTAssertFalse(BackupCrypto.isEncrypted(plain.data))

        try BugService.delete(id: report.id)
        let imported = try BugService.importBackup(data: plain.data, password: nil)
        XCTAssertEqual(imported.found, 1)
        XCTAssertEqual(imported.added, 1)
        XCTAssertFalse(imported.encrypted)
        XCTAssertEqual(BugService.list(query: "").bugs.map(\.title), ["Plain report"])
    }

    // MARK: - Wiki pages

    /// Points `WikiService` at a store in a temporary folder and returns that folder.
    private func makeIsolatedWiki() throws -> URL {
        let folder = try temporaryDirectory()
        WikiService.storeOverride = WikiStore(directory: folder)
        addTeardownBlock {
            WikiService.storeOverride = nil
            WikiService.clock = { Date() }
        }
        return folder
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
                WikiRun(text: "Beta", link: WikiService.linkURL(for: "Beta")),
            ]),
        ])
    }

    func testCreateSaveAndReloadKeepsEveryRunStyle() throws {
        let folder = try makeIsolatedWiki()

        let page = try WikiService.create(title: "Alpha")
        XCTAssertEqual(page.slug, "alpha")
        XCTAssertEqual(page.title, "Alpha")

        let document = sampleDocument()
        try WikiService.save(slug: "alpha", title: "Alpha", document: document)
        XCTAssertEqual(try WikiService.page(slug: "alpha").document, document)

        WikiService.storeOverride = WikiStore(directory: folder)
        XCTAssertEqual(try WikiService.page(slug: "alpha").document, document,
                       "The saved body survives a fresh store instance")
    }

    func testListSearchesTitlesAndBodiesAndCountsThePages() throws {
        _ = try makeIsolatedWiki()
        _ = try WikiService.create(title: "Alpha")
        _ = try WikiService.create(title: "Beta")
        try WikiService.save(slug: "beta", title: "Beta",
                             document: WikiDocument(plain: "A needle in the body"))

        let all = WikiService.list(query: "")
        XCTAssertEqual(all.statusText, "2 pages")
        XCTAssertEqual(Set(all.pages.map(\.slug)), ["alpha", "beta"])

        let found = WikiService.list(query: "NEEDLE")
        XCTAssertEqual(found.pages.map(\.slug), ["beta"])
        XCTAssertEqual(found.statusText, "1 page matching \"NEEDLE\"")
    }

    func testRenameAndDeleteUpdateTheSlugAndTheList() throws {
        _ = try makeIsolatedWiki()
        _ = try WikiService.create(title: "Alpha")

        let renamed = try WikiService.rename(slug: "alpha", title: "Gamma")
        XCTAssertEqual(renamed.slug, "gamma")
        XCTAssertEqual(renamed.title, "Gamma")
        XCTAssertNil(WikiService.resolve(target: "Alpha"))
        XCTAssertEqual(WikiService.resolve(target: "Gamma"), "gamma")
        XCTAssertThrowsError(try WikiService.page(slug: "alpha")) { error in
            XCTAssertEqual((error as? KarmaServiceError)?.errorDescription, "The page no longer exists.")
        }

        let unchanged = try WikiService.rename(slug: "gamma", title: "Gamma")
        XCTAssertEqual(unchanged.slug, "gamma", "An unchanged title leaves the page alone")

        try WikiService.delete(slug: "gamma")
        XCTAssertEqual(WikiService.list(query: "").pages.count, 0)
        XCTAssertThrowsError(try WikiService.delete(slug: "gamma"))
    }

    func testLinkTargetsResolveByNameOrSlug() throws {
        _ = try makeIsolatedWiki()
        _ = try WikiService.create(title: "Beta Page")

        XCTAssertEqual(WikiService.resolve(target: "Beta Page"), "beta-page")
        XCTAssertEqual(WikiService.resolve(target: "beta-page"), "beta-page")
        XCTAssertEqual(WikiService.resolve(target: "beta page"), "beta-page")
        XCTAssertNil(WikiService.resolve(target: "Missing"))

        let link = try XCTUnwrap(WikiService.linkURL(for: "Beta Page"))
        XCTAssertEqual(WikiService.linkTarget(for: link), "Beta Page")
        XCTAssertNil(WikiService.linkTarget(for: "https://example.com/"))
    }

    func testBackupRejectsABlankPassword() throws {
        _ = try makeIsolatedWiki()
        XCTAssertThrowsError(try WikiService.backup(password: "")) { error in
            XCTAssertEqual((error as? KarmaServiceError)?.errorDescription,
                           "The passwords did not match or were blank. No backup was saved.")
        }
    }

    // MARK: - Wiki import

    func testImportSessionAppliesOverwriteRenameAndSkipAnswers() throws {
        try requireZipTools()
        _ = try makeIsolatedWiki()
        _ = try WikiService.create(title: "Keep Me")
        _ = try WikiService.create(title: "Replace Me")
        let archive = try WikiService.backup(password: nil).data

        let overwrite = try WikiService.beginImport(data: archive, password: nil)
        XCTAssertEqual(overwrite.conflicts, ["keep-me", "replace-me"])
        XCTAssertEqual(overwrite.conflictTitles["keep-me"], "Keep Me")
        let overwritten = try WikiService.finishImport(importID: overwrite.importID,
                                                       decisions: ["keep-me": "overwrite", "replace-me": "skip"])
        XCTAssertEqual(overwritten.overwritten, 1)
        XCTAssertEqual(overwritten.skipped, 1)
        XCTAssertEqual(overwritten.imported, 0)
        XCTAssertEqual(overwritten.summary, "Imported: 1 overwritten, 1 skipped.")

        let rename = try WikiService.beginImport(data: archive, password: nil)
        let renamed = try WikiService.finishImport(importID: rename.importID,
                                                   decisions: ["keep-me": "rename"])
        XCTAssertEqual(renamed.renamed, 1)
        XCTAssertEqual(renamed.skipped, 1, "A conflict without an answer is skipped")
        XCTAssertEqual(WikiService.list(query: "").pages.map(\.slug).sorted(), ["keep-me", "keep-me-2", "replace-me"])

        let skipAll = try WikiService.beginImport(data: archive, password: nil)
        let skipped = try WikiService.finishImport(importID: skipAll.importID, decisions: [:])
        XCTAssertEqual(skipped.skipped, 2)
        XCTAssertEqual(skipped.summary, "Imported: 2 skipped.")
        XCTAssertThrowsError(try WikiService.finishImport(importID: skipAll.importID, decisions: [:]),
                             "An import can be finished only once")
    }

    func testEncryptedUploadNeedsItsPassword() throws {
        try requireZipTools()
        _ = try makeIsolatedWiki()
        _ = try WikiService.create(title: "Secret Page")
        let archive = try WikiService.backup(password: "pw").data
        try WikiService.delete(slug: "secret-page")

        XCTAssertThrowsError(try WikiService.beginImport(data: archive, password: nil)) { error in
            guard case WikiService.ImportError.needsPassword = error else {
                return XCTFail("Expected needsPassword, got \(error)")
            }
        }
        XCTAssertThrowsError(try WikiService.beginImport(data: archive, password: "nope")) { error in
            guard case WikiService.ImportError.wrongPassword = error else {
                return XCTFail("Expected wrongPassword, got \(error)")
            }
        }

        let session = try WikiService.beginImport(data: archive, password: "pw")
        XCTAssertEqual(session.conflicts, [])
        let result = try WikiService.finishImport(importID: session.importID, decisions: [:])
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.summary, "Imported: 1 new.")
        XCTAssertEqual(try WikiService.page(slug: "secret-page").info.title, "Secret Page")
    }

    func testUnknownImportIdIsNotFound() throws {
        _ = try makeIsolatedWiki()
        XCTAssertThrowsError(try WikiService.finishImport(importID: "missing", decisions: [:])) { error in
            XCTAssertEqual((error as? KarmaServiceError)?.errorDescription,
                           "The import expired; upload the file again.")
        }
    }

    func testImportExpiresAfterTenMinutes() throws {
        try requireZipTools()
        _ = try makeIsolatedWiki()
        _ = try WikiService.create(title: "Expiring")
        let archive = try WikiService.backup(password: nil).data

        var now = Date()
        WikiService.clock = { now }
        let early = try WikiService.beginImport(data: archive, password: nil)
        now = now.addingTimeInterval(9 * 60)
        let result = try WikiService.finishImport(importID: early.importID, decisions: [:])
        XCTAssertEqual(result.skipped, 1, "Still valid at nine minutes: the page conflicts and is skipped")

        let late = try WikiService.beginImport(data: archive, password: nil)
        now = now.addingTimeInterval(11 * 60)
        XCTAssertThrowsError(try WikiService.finishImport(importID: late.importID, decisions: [:])) { error in
            XCTAssertEqual((error as? KarmaServiceError)?.errorDescription,
                           "The import expired; upload the file again.")
        }
    }
}
