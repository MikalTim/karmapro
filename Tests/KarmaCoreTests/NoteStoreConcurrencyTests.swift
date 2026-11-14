import Foundation
import XCTest
@testable import KarmaCore

final class NoteStoreConcurrencyTests: XCTestCase {
    private func makeSandbox() throws -> (root: URL, fileURL: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-note-concurrency-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return (root, base.appendingPathComponent("store/notes.json"))
    }

    func testConcurrentWritesPreserveEveryPathAndLineOnDisk() throws {
        let sandbox = try makeSandbox()
        let store = NoteStore(fileURL: sandbox.fileURL)
        let workers = 8
        let writesPerWorker = 20

        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            let file = sandbox.root.appendingPathComponent("source-\(worker % 4).c")
            for offset in 0..<writesPerWorker {
                let line = worker * writesPerWorker + offset + 1
                let text = "\(file.lastPathComponent):\(line)"
                XCTAssertTrue(store.setNote(for: file, line: line, text: text))
                XCTAssertEqual(store.note(for: file, line: line), text)
                XCTAssertTrue(store.lineNumbers(for: file).contains(line))
                for note in NotesService.list(store: store, root: sandbox.root).notes {
                    XCTAssertEqual(note.path, sandbox.root.appendingPathComponent(note.file).path)
                    XCTAssertEqual(note.text, "\(note.file):\(note.line)")
                }
            }
        }

        let reloaded = NoteStore(fileURL: sandbox.fileURL)
        XCTAssertEqual(store.allNotes().count, workers * writesPerWorker)
        XCTAssertEqual(reloaded.allNotes().count, workers * writesPerWorker)
        for worker in 0..<workers {
            let file = sandbox.root.appendingPathComponent("source-\(worker % 4).c")
            for offset in 0..<writesPerWorker {
                let line = worker * writesPerWorker + offset + 1
                XCTAssertEqual(reloaded.note(for: file, line: line), "\(file.lastPathComponent):\(line)")
            }
        }
    }

    func testConcurrentImportsAndExportsPreserveWholeBatchesAlongsideWrites() throws {
        let sandbox = try makeSandbox()
        let store = NoteStore(fileURL: sandbox.fileURL)
        let file = sandbox.root.appendingPathComponent("shared.c")
        let workers = 8
        let batchesPerWorker = 10
        let batchCount = workers * batchesPerWorker
        let importStart = 1000

        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            for offset in 0..<batchesPerWorker {
                let batch = worker * batchesPerWorker + offset
                let first = importStart + batch * 2
                let second = first + 1
                let usePortableKeys = worker.isMultiple(of: 2)
                let key = usePortableKeys ? "OriginalProject/shared.c" : file.path
                do {
                    let data = try JSONEncoder().encode([key: ["\(first)": "line \(first)",
                                                               "\(second)": "line \(second)"]])
                    XCTAssertTrue(store.setNote(for: file, line: batch + 1, text: "line \(batch + 1)"))
                    let result = store.importFrom(data: data,
                                                  projectRoot: usePortableKeys ? sandbox.root : nil)
                    XCTAssertEqual(result.count, 2)
                    XCTAssertEqual(result.error, "")
                    XCTAssertEqual(store.note(for: file, line: first), "line \(first)")
                    XCTAssertEqual(store.note(for: file, line: second), "line \(second)")

                    let exported = try NotesService.export(store: store, root: sandbox.root)
                    let raw = try JSONDecoder().decode([String: [String: String]].self, from: exported.data)
                    XCTAssertEqual(Set(raw.keys), ["project/shared.c"])
                    let lines = try XCTUnwrap(raw["project/shared.c"])
                    for (key, text) in lines {
                        let line = try XCTUnwrap(Int(key))
                        XCTAssertEqual(text, "line \(line)")
                        if line >= importStart {
                            // Both rows of each import must appear in the same snapshot.
                            let partner = (line - importStart).isMultiple(of: 2) ? line + 1 : line - 1
                            XCTAssertEqual(lines["\(partner)"], "line \(partner)")
                        }
                    }
                } catch {
                    XCTFail("Concurrent notes import/export failed: \(error)")
                }
            }
        }

        let reloaded = NoteStore(fileURL: sandbox.fileURL)
        XCTAssertEqual(reloaded.allNotes().count, batchCount * 3)
        for batch in 0..<batchCount {
            for line in [batch + 1, importStart + batch * 2, importStart + batch * 2 + 1] {
                XCTAssertEqual(reloaded.note(for: file, line: line), "line \(line)")
            }
        }
    }

    func testConcurrentSameNoteChangesReportExactlyOneMutation() throws {
        let sandbox = try makeSandbox()
        let store = NoteStore(fileURL: sandbox.fileURL)
        let file = sandbox.root.appendingPathComponent("shared.c")
        let written = expectation(description: "Exactly one caller creates the note")
        written.assertForOverFulfill = true
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            if store.setNote(for: file, line: 7, text: "check") {
                written.fulfill()
            }
            XCTAssertEqual(store.note(for: file, line: 7), "check")
        }
        wait(for: [written], timeout: 1)
        XCTAssertEqual(store.lineNumbers(for: file), [7])

        let removed = expectation(description: "Exactly one caller removes the note")
        removed.assertForOverFulfill = true
        DispatchQueue.concurrentPerform(iterations: 16) { caller in
            if store.setNote(for: file, line: 7, text: caller.isMultiple(of: 2) ? nil : "  \n") {
                removed.fulfill()
            }
            XCTAssertNil(store.note(for: file, line: 7))
        }
        wait(for: [removed], timeout: 1)
        XCTAssertTrue(store.lineNumbers(for: file).isEmpty)
        XCTAssertTrue(store.allNotes().isEmpty)
        XCTAssertTrue(NoteStore(fileURL: sandbox.fileURL).allNotes().isEmpty)
    }
}
