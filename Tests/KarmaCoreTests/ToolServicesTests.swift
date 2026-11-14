import Foundation
import XCTest
@testable import KarmaCore

/// Search, package scan, licensing, help and notes services, run against temporary
/// project folders. No network, no real home folder and no real application support data.
final class ToolServicesTests: XCTestCase {

    private func makeProject(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    /// Runs `body` with `XDG_DATA_HOME` set to `path`, which is where `NoteStore()` keeps its file on Linux.
    private func withDataHome<T>(_ path: String, _ body: () throws -> T) rethrows -> T {
        let previous = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        setenv("XDG_DATA_HOME", path, 1)
        defer {
            if let previous {
                setenv("XDG_DATA_HOME", previous, 1)
            } else {
                unsetenv("XDG_DATA_HOME")
            }
        }
        return try body()
    }

    // MARK: - Search in files

    func testSearchIsCaseInsensitiveAndRespectsLanguageAndSkipRules() throws {
        let root = try makeProject([
            "src/main.c": "int main() {\n  printf(\"Hello\");\n}\n",
            "app.py": "print('hello')\n",
            "notes.txt": "HELLO there\n",
            ".hidden.c": "hello\n",
            "logo.png": "hello\n",
        ])

        let all = SearchService.result(term: "hello", root: root, language: nil)
        XCTAssertEqual(all.statusText, "3 matches")
        XCTAssertEqual(Set(all.matches.map(\.relativePath)), ["src/main.c", "app.py", "notes.txt"])
        XCTAssertEqual(all.matches.first { $0.relativePath == "src/main.c" }?.line, 2)

        let cOnly = SearchService.result(term: "HELLO", root: root,
                                         language: Language.supported.first { $0.name == "C" })
        XCTAssertEqual(cOnly.matches.map(\.relativePath), ["src/main.c"])
        XCTAssertEqual(cOnly.statusText, "1 match")

        XCTAssertEqual(SearchService.result(term: "absent", root: root, language: nil).statusText, "No matches")
        XCTAssertEqual(SearchService.result(term: "x", root: nil, language: nil).statusText, "No folder is open.")
    }

    // MARK: - Licensing

    func testLicenseReportNamesTheLicenseFileOfTheProject() throws {
        let root = try makeProject([
            "LICENSE": "MIT License\n\nPermission is hereby granted, free of charge, to any person obtaining a copy.\n",
            "package.json": "{}\n",
        ])

        let report = LicenseService.reportText(root: root)
        XCTAssertEqual(report, LicenseScanner.report(root: root))
        XCTAssertTrue(report.contains("Found License File: LICENSE"))
        XCTAssertTrue(report.contains("• Detected License Type : MIT License"))
        XCTAssertTrue(report.contains("Commercial Use Permitted? : YES"))
        XCTAssertEqual(LicenseService.reportText(root: nil),
                       "No project folder currently open.\nPlease open a project using File > Open... to scan for licenses.")
    }

    // MARK: - Package scan

    func testPackageDetectionListsManifestsAndLockfiles() throws {
        let root = try makeProject([
            "package.json": "{\n  \"dependencies\": {\n    \"lodash\": \"4.17.21\"\n  }\n}\n",
            "requirements.txt": "requests==2.31.0\n",
        ])

        let state = PackageScanService.runDetection(root: root)
        XCTAssertEqual(state.files.map(\.relativePath), ["package.json", "requirements.txt"])
        XCTAssertEqual(state.files.map(\.kind), ["manifest", "lockfile"])
        XCTAssertEqual(state.files[0].label, "package.json — JavaScript/npm (manifest)")
        XCTAssertEqual(state.statusText, "2 package entries in 2 files. Click Scan to query.")
        XCTAssertEqual(state.statusTone, "secondary")
        XCTAssertTrue(state.scanEnabled)
        XCTAssertFalse(state.busy)
    }

    func testProjectWithoutPackageFilesIsReportedAsUnsupported() throws {
        let root = try makeProject(["main.c": "int main(void) { return 0; }\n"])

        let state = PackageScanService.runDetection(root: root)
        XCTAssertTrue(state.files.isEmpty)
        XCTAssertEqual(state.statusText, "The current project is not supported for package scanning")
        XCTAssertEqual(state.statusTone, "warning")
        XCTAssertFalse(state.scanEnabled)
    }

    func testIgnoreKeyHidesAndRestoresTheFindingThroughTheSameDefaultsList() throws {
        let suite = "karma-tool-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let manifest = URL(fileURLWithPath: "/tmp/karma-fixture/package.json")
        let dependency = PackageDependency(name: "lodash", version: "4.17.20", ecosystem: "npm",
                                           fileURL: manifest, line: 3)
        let vulnerability = OSVVulnerability(id: "GHSA-test-0001", summary: "Prototype pollution",
                                             details: nil, aliases: nil, severity: nil, databaseSpecific: nil)
        let key = OSVClient.queryKey(ecosystem: "npm", name: "lodash", version: "4.17.20")
        let findings = PackageScanFindings.make(dependencies: [dependency], vulnerabilities: [key: [vulnerability]])
        let finding = try XCTUnwrap(findings.first)
        XCTAssertEqual(PackageScanFindings.ignoredKey(for: finding), "/tmp/karma-fixture/package.json#3#lodash@4.17.20")

        PackageScanService.setIgnored(key: PackageScanFindings.ignoredKey(for: finding), ignored: true, defaults: defaults)
        XCTAssertEqual(PackageScanFindings.ignoredLines(defaults: defaults), ["/tmp/karma-fixture/package.json#3#lodash@4.17.20"])
        XCTAssertTrue(PackageScanFindings.applyIgnored(findings, defaults: defaults).isEmpty)

        PackageScanService.setIgnored(key: PackageScanFindings.ignoredKey(for: finding), ignored: false, defaults: defaults)
        XCTAssertEqual(PackageScanFindings.applyIgnored(findings, defaults: defaults).count, 1)
    }

    // MARK: - Help

    func testHelpPageHasThePageStructureAndTheSplashImagePath() throws {
        let resources = try makeProject([
            "HelpContent.md": "# Karma Pro Help\n\n![Karma Pro Splash](SplashImage.jpg)\n\n## Usage\n\n- Open a folder\n",
        ])
        let empty = try makeProject([:])
        let previous = KarmaResources.directory
        defer { KarmaResources.directory = previous }

        KarmaResources.directory = resources
        let html = HelpService.html()
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<h1>Karma Pro Help</h1>"))
        XCTAssertTrue(html.contains("<h2>Usage</h2>"))
        XCTAssertTrue(html.contains("src='/api/resources/HelpSplash.jpg'"))

        KarmaResources.directory = empty
        XCTAssertEqual(HelpService.html(), "<h3>Help content not found.</h3>")
    }

    // MARK: - Notes

    func testNotesListExportAndImportRoundTripThroughTheStore() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-notes-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let homeA = base.appendingPathComponent("a").path
        let homeB = base.appendingPathComponent("b").path
        let storeA = withDataHome(homeA) { NoteStore() }
        let storeB = withDataHome(homeB) { NoteStore() }

        let source = try makeProject(["src/a.c": "int a;\n", "b.py": "x = 1\n"])
        let sourceName = source.lastPathComponent
        storeA.setNote(for: source.appendingPathComponent("src/a.c"), line: 6, text: "check")
        storeA.setNote(for: source.appendingPathComponent("b.py"), line: 1, text: "second")
        XCTAssertTrue(FileManager.default.fileExists(atPath: homeA + "/Karma Pro/notes.json"),
                      "the test store must live under the temporary data home")

        let listed = NotesService.list(store: storeA, root: source)
        XCTAssertEqual(listed.root, source.path)
        XCTAssertEqual(listed.notes.map(\.relativePath), ["b.py", "src/a.c"])
        XCTAssertEqual(listed.notes[1].file, "a.c")
        XCTAssertEqual(listed.notes[1].line, 6)
        XCTAssertEqual(listed.notes[1].text, "check")
        XCTAssertEqual(listed.statusText, "2 notes")

        let exported = try NotesService.export(store: storeA, root: source)
        XCTAssertEqual(exported.fileName, "\(sourceName)-notes.codenotes")
        let keys = try JSONDecoder().decode([String: [String: String]].self, from: exported.data)
        XCTAssertEqual(keys["\(sourceName)/src/a.c"], ["6": "check"])

        let recipient = base.appendingPathComponent("Recipient", isDirectory: true)
        try FileManager.default.createDirectory(at: recipient, withIntermediateDirectories: true)
        let imported = NotesService.importData(store: storeB, root: recipient, data: exported.data)
        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(imported.title, "Imported")
        XCTAssertEqual(imported.message, "Merged 2 notes.")

        let copied = NotesService.list(store: storeB, root: recipient)
        XCTAssertEqual(copied.notes.map(\.relativePath), ["b.py", "src/a.c"])
        XCTAssertEqual(copied.notes[1].path, recipient.standardizedFileURL.path + "/src/a.c")
        XCTAssertEqual(copied.statusText, "2 notes")

        let again = NotesService.importData(store: storeB, root: recipient, data: exported.data)
        XCTAssertEqual(again.count, 0)
        XCTAssertEqual(again.message, "No new notes to add.")

        let bad = NotesService.importData(store: storeB, root: recipient, data: Data("not json".utf8))
        XCTAssertEqual(bad.title, "Import Failed")
        XCTAssertEqual(bad.message, "Not a valid Karma Pro notes file.")
    }

    func testNotesUrlImportRejectsAnEmptyAddressBeforeAnyRequest() {
        XCTAssertThrowsError(try NotesService.importNotes(urlString: "   ")) { error in
            XCTAssertEqual((error as? KarmaServiceError)?.errorDescription, "Enter a valid web address.")
        }
    }
}
