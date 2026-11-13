import Foundation
import XCTest
@testable import KarmaCore

/// A throwaway project directory: writes `files` (relative path -> source)
/// under a unique temporary root and removes it again on deinit.
final class ScanFixture {
    let root: URL

    init(_ files: [String: String]) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-tests-\(UUID().uuidString)", isDirectory: true)
        for (path, source) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try source.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func scan(progress: ((Int, Int) -> Void)? = nil,
              isCancelled: (() -> Bool)? = nil) -> [ScanFinding] {
        VulnerabilityScanner.scan(projectRoot: root, progress: progress, isCancelled: isCancelled)
    }
}

extension ScanFinding {
    var fileName: String { fileURL.lastPathComponent }
}

/// Asserts exactly one finding of `category` at `file:line` with the given
/// severity and detecting engine.
func XCTAssertFinding(_ findings: [ScanFinding],
                      file: String, line: Int, category: String,
                      severity: ScanFinding.Severity, engine: String,
                      sourceFile: StaticString = #filePath, sourceLine: UInt = #line) {
    let matches = findings.filter { $0.fileName == file && $0.line == line && $0.category == category }
    guard matches.count == 1, let finding = matches.first else {
        let listing = findings.map { "\($0.fileName):\($0.line) \($0.category) [\($0.scanningSource)]" }
        XCTFail("expected one \(category) at \(file):\(line), got \(matches.count); all findings: \(listing)",
                file: sourceFile, line: sourceLine)
        return
    }
    XCTAssertEqual(finding.severity, severity, "severity of \(category) at \(file):\(line)",
                   file: sourceFile, line: sourceLine)
    XCTAssertEqual(finding.scanningSource, engine, "engine of \(category) at \(file):\(line)",
                   file: sourceFile, line: sourceLine)
}
