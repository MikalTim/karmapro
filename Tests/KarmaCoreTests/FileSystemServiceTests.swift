import Foundation
import XCTest
@testable import KarmaCore

final class FileSystemServiceTests: XCTestCase {

    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-fs-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        for folder in ["beta", "Alpha", ".hidden-folder"] {
            try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for file in ["zeta.txt", "apple.c", ".env"] {
            try "x".write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? fm.removeItem(at: root) }
        return root
    }

    func testFoldersComeFirstAndHiddenNamesAreLeftOut() throws {
        let root = try makeFolder()

        let listing = try FileSystemService.list(path: root.path, includeFiles: true, includeHidden: false)

        XCTAssertEqual(listing.entries.map(\.name), ["Alpha", "beta", "apple.c", "zeta.txt"])
        XCTAssertEqual(listing.entries.map(\.isDirectory), [true, true, false, false])
        XCTAssertEqual(listing.parent, root.deletingLastPathComponent().standardizedFileURL.path)
    }

    func testFilesAreLeftOutUnlessAskedForAndHiddenNamesCanBeShown() throws {
        let root = try makeFolder()

        let foldersOnly = try FileSystemService.list(path: root.path, includeFiles: false, includeHidden: true)

        XCTAssertEqual(foldersOnly.entries.map(\.name), [".hidden-folder", "Alpha", "beta"])
    }

    func testAFileOrMissingPathIsNotAFolder() throws {
        let root = try makeFolder()

        XCTAssertThrowsError(try FileSystemService.list(path: root.appendingPathComponent("zeta.txt").path,
                                                        includeFiles: true, includeHidden: false))
        XCTAssertThrowsError(try FileSystemService.list(path: root.appendingPathComponent("missing").path,
                                                        includeFiles: true, includeHidden: false))
    }
}
