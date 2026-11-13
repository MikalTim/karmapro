import Foundation
import XCTest
@testable import KarmaCore

/// The services that used to be macOS-only and now run everywhere: the RTF
/// wiki format, encrypted backups, token storage and the resource lookup.
final class PortableServicesTests: XCTestCase {

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-portable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - WikiRTF

    func testDecodesAnRTFWrittenByCocoa() {
        // The structure NSAttributedString produces: font table, colour table,
        // a HYPERLINK field, \uc0 unicode escapes and a backslash paragraph end.
        let rtf = """
            {\\rtf1\\ansi\\ansicpg1252\\cocoartf2580
            \\cocoatextscaling0\\cocoaplatform0{\\fonttbl\\f0\\fswiss\\fcharset0 Helvetica;\\f1\\fmodern\\fcharset0 Menlo-Regular;}
            {\\colortbl;\\red255\\green255\\blue255;}
            {\\*\\expandedcolortbl;;}
            \\pard\\pardeftab720\\partightenfactor0
            \\f0\\b\\fs40 \\cf0 Title\\
            \\f0\\b0\\fs28 Plain \\i italic\\i0  and \\ul under\\ulnone  and \\f1 code\\f0  with caf\\'e9 \\uc0\\u8212  dash\\
            See {\\field{\\*\\fldinst{HYPERLINK "wiki://page/Other%20Page"}}{\\fldrslt \\ul Other Page}}.}
            """
        let document = WikiRTF.decode(Data(rtf.utf8))

        XCTAssertEqual(document.paragraphs.count, 3)
        XCTAssertEqual(document.paragraphs[0].runs, [WikiRun(text: "Title", bold: true, heading: true)])

        let second = document.paragraphs[1].runs
        XCTAssertEqual(second.map(\.text).joined(), "Plain italic and under and code with caf\u{e9} \u{2014} dash")
        XCTAssertTrue(second.contains { $0.text == "italic" && $0.italic && !$0.bold })
        XCTAssertTrue(second.contains { $0.text == "under" && $0.underline })
        XCTAssertTrue(second.contains { $0.text == "code" && $0.code })
        XCTAssertTrue(second.allSatisfy { !$0.heading })

        let third = document.paragraphs[2].runs
        XCTAssertEqual(third.map(\.text).joined(), "See Other Page.")
        let link = third.first { $0.link != nil }
        XCTAssertEqual(link?.text, "Other Page")
        XCTAssertEqual(link?.link, "wiki://page/Other%20Page")
    }

    func testEncodeThenDecodeKeepsEveryFormat() {
        let original = WikiDocument(paragraphs: [
            WikiParagraph(runs: [WikiRun(text: "Heading", bold: true, heading: true)]),
            WikiParagraph(runs: [
                WikiRun(text: "plain "),
                WikiRun(text: "bold", bold: true),
                WikiRun(text: " "),
                WikiRun(text: "both", bold: true, italic: true, underline: true),
                WikiRun(text: " "),
                WikiRun(text: "let x = 1", code: true),
            ]),
            WikiParagraph(),
            WikiParagraph(runs: [
                WikiRun(text: "braces {} and \\ backslash, é, 日本, 😀"),
                WikiRun(text: "Beta", link: "wiki://page/Beta"),
            ]),
        ])
        let decoded = WikiRTF.decode(WikiRTF.encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testEmptyDocumentRoundTripsToEmpty() {
        XCTAssertEqual(WikiRTF.decode(WikiRTF.encode(WikiDocument())), WikiDocument())
        XCTAssertEqual(WikiRTF.plainText(WikiRTF.encode(WikiDocument())), "")
    }

    func testPlainTextJoinsParagraphsWithNewlines() {
        let data = WikiRTF.encode(WikiDocument(plain: "one\ntwo\n\nfour"))
        XCTAssertEqual(WikiRTF.plainText(data), "one\ntwo\n\nfour")
    }

    func testRunsDecodeWithMissingFlags() throws {
        let json = Data(#"{"paragraphs":[{"runs":[{"text":"x","bold":true}]}]}"#.utf8)
        let document = try JSONDecoder().decode(WikiDocument.self, from: json)
        XCTAssertEqual(document.paragraphs[0].runs, [WikiRun(text: "x", bold: true)])
    }

    // MARK: - WikiStore

    func testWikiStoreKeepsRTFBytesAndFindsTextInPages() throws {
        let store = WikiStore(directory: try temporaryDirectory())
        let body = WikiRTF.encode(WikiDocument(paragraphs: [
            WikiParagraph(runs: [WikiRun(text: "Needle", bold: true), WikiRun(text: " in a haystack")]),
        ]))
        let slug = store.createPage(title: "Alpha", bodyRTF: body)

        XCTAssertEqual(store.bodyRTF(slug: slug), body)
        XCTAssertEqual(store.search("needle").map(\.slug), [slug])
        XCTAssertTrue(store.search("absent").isEmpty)
    }

    func testImportConflictsListsExistingPagesAndImportAppliesDecisions() throws {
        let store = WikiStore(directory: try temporaryDirectory())
        _ = store.createPage(title: "Keep", bodyRTF: WikiRTF.encode(WikiDocument(plain: "local keep")))
        _ = store.createPage(title: "Replace", bodyRTF: WikiRTF.encode(WikiDocument(plain: "local replace")))

        // A plain folder in the backup layout: manifest.json plus pages/<slug>.rtf.
        let backup = try temporaryDirectory()
        let pages = backup.appendingPathComponent("pages", isDirectory: true)
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        let infos = ["keep", "replace", "fresh"].map {
            WikiStore.PageInfo(slug: $0, title: $0.capitalized, created: 1, updated: 2)
        }
        try JSONEncoder().encode(infos).write(to: backup.appendingPathComponent("manifest.json"))
        for info in infos {
            try WikiRTF.encode(WikiDocument(plain: "imported \(info.slug)"))
                .write(to: pages.appendingPathComponent("\(info.slug).rtf"))
        }
        let folder = URL(fileURLWithPath: backup.path, isDirectory: true)

        XCTAssertEqual(try store.importConflicts(from: folder, password: nil), ["keep", "replace"])

        let decisions: [String: WikiStore.Conflict] = ["keep": .skip, "replace": .overwrite]
        let result = try store.import(from: folder, password: nil) { decisions[$0] ?? .skip }

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.overwritten, 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(store.bodyPlain(slug: "keep"), "local keep")
        XCTAssertEqual(store.bodyPlain(slug: "replace"), "imported replace")
        XCTAssertEqual(store.bodyPlain(slug: "fresh"), "imported fresh")
    }

    func testConflictDecisionsDecodeFromTheirRawValues() throws {
        let decoded = try JSONDecoder().decode([String: WikiStore.Conflict].self,
                                               from: Data(#"{"a":"overwrite","b":"rename","c":"skip"}"#.utf8))
        XCTAssertEqual(decoded, ["a": .overwrite, "b": .rename, "c": .skip])
    }

    // MARK: - BackupCrypto

    func testBackupRoundTripAndWrongPassword() throws {
        let payload = Data(#"[{"id":"1","title":"secret"}]"#.utf8)
        let sealed = try BackupCrypto.seal(payload, password: "correct horse")

        XCTAssertTrue(BackupCrypto.isEncrypted(sealed))
        XCTAssertFalse(BackupCrypto.isEncrypted(payload))
        XCTAssertFalse(String(decoding: sealed, as: UTF8.self).contains("secret"))
        XCTAssertEqual(try BackupCrypto.open(sealed, password: "correct horse"), payload)

        XCTAssertThrowsError(try BackupCrypto.open(sealed, password: "wrong")) { error in
            guard case BackupError.wrongPassword = error else {
                return XCTFail("expected wrongPassword, got \(error)")
            }
        }
        XCTAssertThrowsError(try BackupCrypto.seal(payload, password: "")) { error in
            guard case BackupError.emptyPassword = error else {
                return XCTFail("expected emptyPassword, got \(error)")
            }
        }
    }

    // MARK: - FilePRTokenStorage

    func testTokenFileIsPrivateAndHoldsTokens() throws {
        let file = try temporaryDirectory().appendingPathComponent("tokens/PullRequestTokens.json")
        let storage = FilePRTokenStorage(fileURL: file)

        try storage.setToken("s3cret", identity: "github.com/octo")
        try storage.setToken("other", identity: "gitlab.com/cat")

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        // A second instance reads what the first wrote.
        let reread = FilePRTokenStorage(fileURL: file)
        XCTAssertEqual(reread.token(identity: "github.com/octo", prompt: false), "s3cret")

        try storage.deleteToken(identity: "github.com/octo")
        storage.invalidateSessionCache()
        XCTAssertNil(storage.token(identity: "github.com/octo", prompt: false))
        XCTAssertEqual(storage.token(identity: "gitlab.com/cat", prompt: false), "other")
    }

    // MARK: - KarmaResources

    func testResourceLookupUsesTheConfiguredFolder() throws {
        let folder = try temporaryDirectory()
        try Data("{}".utf8).write(to: folder.appendingPathComponent("AIPrompts.json"))
        let plist: [String: Any] = ["CFBundleShortVersionString": "9.9"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: folder.appendingPathComponent("Info.plist"))

        let saved = KarmaResources.directory
        KarmaResources.directory = folder
        defer { KarmaResources.directory = saved }

        XCTAssertEqual(KarmaResources.shortVersion, "9.9")
        XCTAssertTrue(KarmaResources.isAvailable)
        XCTAssertNotNil(KarmaResources.url(forResource: "AIPrompts", withExtension: "json"))
        XCTAssertNil(KarmaResources.url(forResource: "Missing", withExtension: "json"))
        XCTAssertNil(KarmaResources.url(forResource: "AIPrompts", withExtension: "json", subdirectory: "Models"))
    }
}
