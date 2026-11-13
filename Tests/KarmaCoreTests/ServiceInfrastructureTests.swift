import Foundation
import XCTest
@testable import KarmaCore

/// The event bus, job center and workspace that every feature service sits on.
final class ServiceInfrastructureTests: XCTestCase {

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
            .appendingPathComponent("karma-service-\(UUID().uuidString)", isDirectory: true)
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    // MARK: - Event bus

    func testEventBusDeliversToEverySubscriberUntilUnsubscribed() {
        let bus = KarmaEventBus()
        var first: [String] = []
        var second: [String] = []
        let a = bus.subscribe { type, data in first.append("\(type) \(String(decoding: data, as: UTF8.self))") }
        _ = bus.subscribe { type, _ in second.append(type) }

        bus.post("bugs.changed", BugsChangedEvent(openCount: 3))
        bus.unsubscribe(a)
        bus.post("notes.changed")

        XCTAssertEqual(first, ["bugs.changed {\"openCount\":3}"])
        XCTAssertEqual(second, ["bugs.changed", "notes.changed"])
    }

    // MARK: - Job center

    func testJobCompletesWithItsResultAndPostsFinished() throws {
        let bus = KarmaEventBus()
        let center = KarmaJobCenter(bus: bus)
        var events: [String] = []
        let lock = NSLock()
        _ = bus.subscribe { type, data in
            lock.lock(); events.append("\(type) \(String(decoding: data, as: UTF8.self))"); lock.unlock()
        }

        let id = center.start(kind: "demo") { context in
            context.progress(done: 5, total: 10, stage: "half")
            context.progress(done: 10, total: 10, stage: "all")
            return Data("{\"rows\":2}".utf8)
        }
        waitUntil("job completes") { center.job(id)?.status == "completed" }

        let job = try XCTUnwrap(center.job(id))
        XCTAssertEqual(job.kind, "demo")
        XCTAssertEqual(job.done, 10)
        XCTAssertEqual(job.total, 10)
        XCTAssertEqual(String(decoding: job.encoded(), as: UTF8.self),
                       "{\"done\":10,\"id\":\"\(id)\",\"kind\":\"demo\",\"stage\":\"all\",\"status\":\"completed\",\"total\":10,\"result\":{\"rows\":2}}")
        lock.lock()
        defer { lock.unlock() }
        XCTAssertEqual(events.last, "job.finished {\"id\":\"\(id)\",\"kind\":\"demo\",\"status\":\"completed\"}")
        // The first and the last progress are always posted; the one in between falls inside the 250 ms throttle.
        XCTAssertTrue(events.first?.hasPrefix("job.progress") == true)
    }

    func testThrownErrorFailsTheJobWithItsDescription() throws {
        let center = KarmaJobCenter(bus: KarmaEventBus())
        let id = center.start(kind: "demo") { _ in throw KarmaServiceError.invalid("bad input") }
        waitUntil("job fails") { center.job(id)?.status == "failed" }
        let job = try XCTUnwrap(center.job(id))
        XCTAssertEqual(job.error, "bad input")
        XCTAssertNil(job.resultJSON)
    }

    func testCancelFlipsTheContextAndTheEngineTokenAndKeepsThePartialResult() throws {
        let center = KarmaJobCenter(bus: KarmaEventBus())
        let started = DispatchSemaphore(value: 0)
        var tokenSeen = false
        let id = center.start(kind: "demo") { context in
            let token = context.cancellationToken()
            started.signal()
            while !context.isCancelled { Thread.sleep(forTimeInterval: 0.005) }
            tokenSeen = token.isCancelled
            return Data("{\"partial\":true}".utf8)
        }
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(center.cancel(id)?.status, "running")
        waitUntil("job is cancelled") { center.job(id)?.status == "cancelled" }

        XCTAssertTrue(tokenSeen)
        XCTAssertEqual(center.job(id)?.resultJSON, Data("{\"partial\":true}".utf8))
        XCTAssertNil(center.cancel("missing"))
    }

    // MARK: - Workspace and project service

    func testOpeningAProjectBuildsTheIndexAndListsItsFiles() throws {
        let root = try makeProject([
            "src/main.c": "int add(int a, int b) { return a + b; }\n",
            "src/util.py": "def helper():\n    return 1\n",
            "node_modules/skip.js": "var x;\n",
            "README.md": "# demo\n"
        ])
        let workspace = KarmaWorkspace.shared
        XCTAssertThrowsError(try workspace.open(root: root.appendingPathComponent("missing").path)) { error in
            guard case KarmaServiceError.notADirectory = error else { return XCTFail("\(error)") }
        }

        let jobID = try ProjectService.open(path: root.path)
        waitUntil("index is ready") { ProjectService.info().indexState == "ready" }
        XCTAssertEqual(KarmaJobCenter.shared.job(jobID)?.status, "completed")

        let info = ProjectService.info()
        XCTAssertEqual(info.root, root.standardizedFileURL.path)
        XCTAssertEqual(info.name, root.lastPathComponent)
        XCTAssertEqual(info.indexJobId, jobID)
        XCTAssertEqual(workspace.read { $0.sourceIndex?.entries.count }, 2)
        XCTAssertNotNil(workspace.read { $0.definitionIndex })

        // The whole tree, with folders first and ignored folders left out.
        let everything = try ProjectService.tree(language: nil, query: nil)
        XCTAssertEqual(everything.root?.children?.map(\.name), ["src", "README.md"])
        XCTAssertEqual(everything.root?.children?.first?.children?.map(\.name), ["main.c", "util.py"])

        // A language keeps only its files, and only the folders that still contain one.
        let python = try ProjectService.tree(language: "Python", query: nil)
        XCTAssertEqual(python.root?.children?.map(\.name), ["src"])
        XCTAssertEqual(python.root?.children?.first?.children?.map(\.name), ["util.py"])
        XCTAssertThrowsError(try ProjectService.tree(language: "Klingon", query: nil))

        // A search is a flat list over the whole project, whatever the language.
        let found = try ProjectService.tree(language: "Python", query: " MAIN ")
        XCTAssertNil(found.root)
        XCTAssertEqual(found.matches?.map(\.name), ["main.c"])
        XCTAssertEqual(found.matches?.first?.path, root.standardizedFileURL.appendingPathComponent("src/main.c").path)

        workspace.close()
        XCTAssertNil(ProjectService.info().root)
        XCTAssertThrowsError(try workspace.requireRoot()) { error in
            guard case KarmaServiceError.noProject = error else { return XCTFail("\(error)") }
        }
        XCTAssertNil(try ProjectService.tree(language: nil, query: nil).root)
    }

    func testReopeningCancelsTheEarlierIndexBuild() throws {
        let first = try makeProject(["a.c": "int a;\n"])
        let second = try makeProject(["b.py": "x = 1\n"])
        let workspace = KarmaWorkspace.shared

        _ = try workspace.open(root: first.path)
        let secondJob = try workspace.open(root: second.path)
        waitUntil("the second index is ready") { workspace.info().indexState == "ready" }

        XCTAssertEqual(workspace.info().indexJobId, secondJob)
        XCTAssertEqual(workspace.read { $0.sourceIndex?.root }, second.standardizedFileURL)
        workspace.close()
    }
}
