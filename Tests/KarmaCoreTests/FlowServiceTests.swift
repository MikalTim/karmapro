// by cipher.org.uk
import Foundation
import XCTest
@testable import KarmaCore

/// The flow, data-flow, variable-flow, reachability, complexity, backtrace and class-usage services.
final class FlowServiceTests: XCTestCase {

    private static let cSource = """
    #include <stdio.h>

    int helper(int v) {
        return v + 1;
    }

    int compute(int n) {
        int total = 0;
        if (n > 0) {
            total = helper(n);
        } else {
            total = -1;
        }
        while (total < 10) {
            total = total + 1;
        }
        return total;
    }

    int main(void) {
        return compute(3);
    }

    """

    private static let javaSource = """
    public class Main {
        public static void main(String[] args) {
            Widget first = new Widget(1);
            Widget second = new Widget(2);
        }
    }

    class Widget {
        Widget(int id) {}
    }

    """

    private static let pythonSource = """
    import os

    def run(cmd):
        os.system(cmd)

    """

    /// Polls until `condition` holds, so tests do not depend on how fast a background job runs.
    private func waitUntil(_ message: String, timeout: TimeInterval = 30, _ condition: () -> Bool,
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

    /// Writes the files into a fresh temporary folder that is removed after the test.
    private func makeProject(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-flow-\(UUID().uuidString)", isDirectory: true)
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    /// Opens the fixture as the workspace project and waits until its index (and the caches the graphs use) is ready.
    private func openProject(_ files: [String: String]) throws -> URL {
        let root = try makeProject(files)
        try KarmaWorkspace.shared.open(root: root.path)
        waitUntil("the index is ready") { KarmaWorkspace.shared.info().indexState == "ready" }
        return root
    }

    /// Waits for a job to finish and decodes its result.
    private func result<T: Decodable>(_ jobID: String, as type: T.Type) throws -> T {
        waitUntil("job \(jobID) finishes") {
            ["completed", "failed", "cancelled"].contains(KarmaJobCenter.shared.job(jobID)?.status ?? "")
        }
        let job = try XCTUnwrap(KarmaJobCenter.shared.job(jobID))
        XCTAssertEqual(job.status, "completed", job.error ?? "")
        return try KarmaJSON.decoder.decode(type, from: try XCTUnwrap(job.resultJSON))
    }

    /// The job center posts its first progress event synchronously, before dispatching work.
    /// Cancel there to cover the pre-start race without depending on fixture size or sleeps.
    private func startCancelledJob(kind: String, _ start: () throws -> String) throws -> String {
        let finished = expectation(description: "\(kind) cancellation finishes")
        let subscription = KarmaEventBus.shared.subscribe { type, data in
            guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["kind"] as? String == kind,
                  let id = event["id"] as? String else { return }
            if type == "job.progress", event["stage"] as? String == "" {
                KarmaJobCenter.shared.cancel(id)
            } else if type == "job.finished" {
                finished.fulfill()
            }
        }
        defer { KarmaEventBus.shared.unsubscribe(subscription) }
        let id = try start()
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(KarmaJobCenter.shared.job(id)?.status, "cancelled")
        XCTAssertNil(KarmaJobCenter.shared.job(id)?.resultJSON)
        return id
    }

    // MARK: - Flow panel

    func testFlowChartHasDecisionBranchesAndLoopBackEdge() throws {
        let root = try makeProject(["main.c": Self.cSource])
        let file = root.appendingPathComponent("main.c").path

        let flow = try FlowService.flow(path: file, function: "compute")

        let chart = try XCTUnwrap(flow.chart)
        let decisions = chart.nodes.filter { $0.kind == "decision" }.map { $0.label }
        XCTAssertTrue(decisions.contains("if n > 0"), "decisions were \(decisions)")
        XCTAssertTrue(decisions.contains("while total < 10"), "decisions were \(decisions)")
        XCTAssertTrue(chart.edges.contains { $0.branch == "T" }, "no true branch")
        XCTAssertTrue(chart.edges.contains { $0.branch == "F" }, "no false branch")
        XCTAssertTrue(chart.edges.contains { $0.isBackEdge }, "the while loop has no back edge")
        XCTAssertEqual(flow.complexity, 3)
        XCTAssertEqual(flow.callees, ["helper"])
        XCTAssertEqual(flow.lineCount, Self.cSource.components(separatedBy: "\n").count)
    }

    func testFlowIsEmptyForAFunctionThatDoesNotExist() throws {
        let root = try makeProject(["main.c": Self.cSource])
        let flow = try FlowService.flow(path: root.appendingPathComponent("main.c").path, function: "missing")
        XCTAssertNil(flow.complexity)
        XCTAssertNil(flow.chart)
        XCTAssertTrue(flow.callees.isEmpty)
    }

    func testFlowAnalysesTheOverloadAtTheClickedOffset() throws {
        let source = """
        int pick(int a) {
            return a;
        }
        int pick(int a, int b) {
            if (a > b) {
                return a;
            }
            return b;
        }
        """
        let root = try makeProject(["pick.cpp": source])
        let file = root.appendingPathComponent("pick.cpp").path
        let second = (source as NSString).range(of: "pick(int a, int b)").location

        let clicked = try FlowService.flow(path: file, function: "pick", location: second + 1)
        let first = try FlowService.flow(path: file, function: "pick")
        let outside = try FlowService.flow(path: file, function: "pick", location: source.count - 1)

        XCTAssertEqual(clicked.complexity, 2, "the clicked overload has the if")
        XCTAssertEqual(first.complexity, 1, "without a location the first overload is used")
        XCTAssertEqual(outside.complexity, 1, "a location inside no name falls back to the first overload")
    }

    // MARK: - Reachability

    func testReachabilityJobReachesTargetFromLocalEntry() throws {
        let root = try openProject(["main.c": Self.cSource])
        let file = root.appendingPathComponent("main.c").path

        let jobID = try FlowService.reachability(path: file, function: "helper")
        let reach = try result(jobID, as: FlowService.ReachabilityDTO.self)

        XCTAssertEqual(reach.windowTitle, "Reachability — helper")
        XCTAssertTrue(reach.localReachable)
        XCTAssertFalse(reach.remoteReachable)
        let graph = try XCTUnwrap(reach.graph)
        let edges = Set(graph.callEdges.map { "\($0.from)>\($0.to)" })
        XCTAssertTrue(edges.contains("Local>main"), "edges were \(edges)")
        XCTAssertTrue(edges.contains("main>compute"), "edges were \(edges)")
        XCTAssertTrue(edges.contains("compute>helper"), "edges were \(edges)")
        XCTAssertEqual(graph.highlight, "helper")
        XCTAssertEqual(graph.layoutDirection, "topToBottom")
        XCTAssertEqual(graph.layoutSourceNodes, ["Local"])
        XCTAssertTrue(graph.nodes.contains { $0.name == "Local" && $0.isOrigin })
    }

    // MARK: - Class usage

    func testClassUsageJobListsEveryInstantiation() throws {
        let root = try openProject(["Main.java": Self.javaSource])

        let jobID = try FlowService.classUsage(className: "Widget")
        let usage = try result(jobID, as: FlowService.ClassUsageDTO.self)

        XCTAssertEqual(usage.windowTitle, "Instantiations of Widget")
        XCTAssertNil(usage.emptyMessage)
        XCTAssertEqual(usage.sites.map { $0.line }, [3, 4])
        XCTAssertTrue(usage.sites.allSatisfy { $0.snippet.hasPrefix("new Widget(") })
        XCTAssertEqual(usage.sites.first?.path, root.appendingPathComponent("Main.java").standardizedFileURL.path)
        XCTAssertEqual(usage.status, "2 instantiation(s) of “Widget” — click a node to open it")
        XCTAssertEqual(usage.graph?.animatedOnlyEdges, true)
    }

    func testClassUsageJobCancelledBeforeWorkDoesNotReturnScannedSites() throws {
        _ = try openProject(["Main.java": Self.javaSource])
        _ = try startCancelledJob(kind: "class-usage") {
            try FlowService.classUsage(className: "Widget")
        }
    }

    func testCancelledOlderEntrySearchCannotPublishAfterNewerSearchFinishes() throws {
        _ = try openProject([
            "input.c": "void handle(int fd) { char buf[16]; recv(fd, buf, 16, 0); }\n"
        ])
        let newerFinished = DispatchSemaphore(value: 0)
        let olderFinished = expectation(description: "Older cancelled search finishes")
        let eventLock = NSLock()
        var olderID: String?
        var newerID: String?
        var nestedError: Error?
        let subscription = KarmaEventBus.shared.subscribe { type, data in
            guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["kind"] as? String == "entry-points",
                  let id = event["id"] as? String else { return }
            eventLock.lock()
            let first = olderID == nil && type == "job.progress"
            if first { olderID = id }
            let old = olderID
            eventLock.unlock()
            if first {
                // The old worker is not dispatched until this initial event returns.
                // Complete a newer real search first, then let the cancelled old job run.
                KarmaJobCenter.shared.cancel(id)
                do { newerID = try EntryPointsService.shared.start() }
                catch { nestedError = error }
                XCTAssertEqual(newerFinished.wait(timeout: .now() + 5), .success)
            } else if type == "job.finished" {
                if id == old { olderFinished.fulfill() }
                else { newerFinished.signal() }
            }
        }
        defer { KarmaEventBus.shared.unsubscribe(subscription) }
        let id = try EntryPointsService.shared.start()
        wait(for: [olderFinished], timeout: 5)
        XCTAssertNil(nestedError)
        XCTAssertEqual(KarmaJobCenter.shared.job(id)?.status, "cancelled")
        XCTAssertNil(KarmaJobCenter.shared.job(id)?.resultJSON)
        let newer = try XCTUnwrap(newerID.flatMap { KarmaJobCenter.shared.job($0) })
        XCTAssertEqual(newer.status, "completed")
        let published = try KarmaJSON.decoder.decode(EntryPointsService.EntryPointsStateDTO.self,
                                                     from: try XCTUnwrap(newer.resultJSON))
        let current = EntryPointsService.shared.state()
        XCTAssertEqual(current.countText, published.countText)
        XCTAssertEqual(current.groups.flatMap(\.sites).map(\.id), published.groups.flatMap(\.sites).map(\.id))
        XCTAssertFalse(current.busy)
    }

    func testCancelledEntrySearchDoesNotPublishOrReplaceNewSearch() throws {
        _ = try openProject([
            "input.c": "void handle(int fd) { char buf[16]; recv(fd, buf, 16, 0); }\n"
        ])
        _ = try startCancelledJob(kind: "entry-points") { try EntryPointsService.shared.start() }
        XCTAssertFalse(EntryPointsService.shared.state().busy)
        XCTAssertTrue(EntryPointsService.shared.state().groups.isEmpty)
        XCTAssertEqual(EntryPointsService.shared.state().progressDone, 0)

        let state = try result(EntryPointsService.shared.start(), as: EntryPointsService.EntryPointsStateDTO.self)
        let site = try XCTUnwrap(state.groups.flatMap(\.sites).first { $0.apiName == "recv" })
        _ = try startCancelledJob(kind: "entry-points-indirect") {
            try EntryPointsService.shared.setIndirect(true)
        }
        XCTAssertEqual(EntryPointsService.shared.state().groups.flatMap(\.sites).map(\.id),
                       state.groups.flatMap(\.sites).map(\.id))
        XCTAssertFalse(EntryPointsService.shared.state().busy)
        _ = try startCancelledJob(kind: "entry-points-trace") {
            try EntryPointsService.shared.trace(siteID: site.id)
        }
        XCTAssertNil(EntryPointsService.shared.state().trace)

        let newer = try result(EntryPointsService.shared.start(), as: EntryPointsService.EntryPointsStateDTO.self)
        XCTAssertEqual(EntryPointsService.shared.state().countText, newer.countText)
        XCTAssertEqual(newer.groups.flatMap(\.sites).map(\.id), [site.id])
    }

    func testEntryTraceTraversalCancelsInsideFunctionBeforeFollowingCalls() throws {
        let root = try makeProject(["main.c": Self.cSource])
        let tracer = VariableFlowTracer(projectRoot: root)
        let offset = (Self.cSource as NSString).range(of: "n > 0").location
        var checks = 0
        let trace = tracer.trace(variableName: "n", in: root.appendingPathComponent("main.c"),
                                 charIndex: offset, isCancelled: {
            checks += 1
            return checks >= 4
        })
        XCTAssertEqual(checks, 4)
        XCTAssertTrue(trace.nodes.isEmpty)
        XCTAssertTrue(trace.edges.isEmpty)
    }

    // MARK: - Backtrace

    func testBacktraceResolvesPythonFrameToProjectFile() throws {
        let root = try openProject(["app.py": Self.pythonSource])
        let trace = """
        Traceback (most recent call last):
          File "app.py", line 4, in run
            os.system(cmd)
        """

        let backtrace = try FlowService.backtrace(text: trace)

        let frame = try XCTUnwrap(backtrace.frames.first)
        XCTAssertEqual(frame.functionName, "run")
        XCTAssertEqual(frame.line, 4)
        XCTAssertEqual(frame.path, root.appendingPathComponent("app.py").standardizedFileURL.path)
        XCTAssertNil(backtrace.warning)
    }

    func testBacktraceWarnsForFrameOutsideTheProject() throws {
        _ = try openProject(["app.py": Self.pythonSource])
        let backtrace = try FlowService.backtrace(text: "  File \"missing.py\", line 2, in gone\n")

        XCTAssertNil(backtrace.frames.first?.path)
        XCTAssertEqual(backtrace.warning?.messageText, "Some files were not found in the open project")
    }

    // MARK: - Variable flow

    func testVariableFlowJobCompletes() throws {
        let root = try openProject(["main.c": Self.cSource])
        let file = root.appendingPathComponent("main.c").path
        let offset = (Self.cSource as NSString).range(of: "n > 0").location

        let jobID = try FlowService.variableFlow(path: file, location: offset, variable: "n")
        let flow = try result(jobID, as: FlowService.VariableFlowDTO.self)

        XCTAssertEqual(flow.variableName, "n")
        XCTAssertEqual(flow.windowTitle, "Variable Flow — n")
        XCTAssertFalse(flow.nodes.isEmpty)
        XCTAssertEqual(flow.nodes.first(where: { $0.isStart })?.functionName, "compute")
    }
}
