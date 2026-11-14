// by cipher.org.uk
#if WebServer
import Foundation
import KarmaCore
import Vapor
import XCTVapor
@testable import KarmaServer

final class GraphRoutesTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        // The workspace is process-wide: every test starts with no project open.
        KarmaWorkspace.shared.close()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-graph-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        KarmaWorkspace.shared.close()
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - Helpers

    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        registerGraphRoutes(app.grouped("api").grouped(KarmaErrorMiddleware()))
        return app
    }

    /// The response of one request, copied out of the test closure.
    private final class Reply {
        var status: HTTPStatus = .ok
        var body = Data()

        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        }
    }

    private func send(_ app: Application, _ method: HTTPMethod, _ path: String,
                      json: [String: Any]? = nil) async throws -> Reply {
        let reply = Reply()
        var headers: HTTPHeaders = [:]
        var body: ByteBuffer?
        if let json {
            headers.add(name: .contentType, value: "application/json")
            body = ByteBuffer(data: try JSONSerialization.data(withJSONObject: json))
        }
        try await app.test(method, path, headers: headers, body: body) { res async throws in
            reply.status = res.status
            reply.body = Data(res.body.readableBytesView)
        }
        return reply
    }

    private func writeFile(_ name: String, _ text: String) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func query(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private struct PollTimedOut: Error {}

    /// Polls the job centre directly until the job leaves the running state.
    private func finishedJob(_ id: String) async throws -> JobDTO {
        for _ in 0..<600 {
            if let job = KarmaJobCenter.shared.job(id), job.status != "running" {
                return job
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("job \(id) did not finish in time")
        throw PollTimedOut()
    }

    // MARK: - Caller mistakes

    func testMissingParametersAreBadRequestsWithJSONErrors() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let noFunction = try await send(app, .GET, "api/flow?path=\(query("/tmp/none.c"))")
        XCTAssertEqual(noFunction.status, .badRequest)
        XCTAssertNotNil(noFunction.json["error"] as? String)

        let emptyPath = try await send(app, .GET, "api/dataflow?path=&function=main")
        XCTAssertEqual(emptyPath.status, .badRequest)
        XCTAssertNotNil(emptyPath.json["error"] as? String)

        let noBody = try await send(app, .POST, "api/variable-flow")
        XCTAssertEqual(noBody.status, .badRequest)
        XCTAssertNotNil(noBody.json["error"] as? String)

        let noFunctionInBody = try await send(app, .POST, "api/sim/load", json: ["path": "/tmp/none.c"])
        XCTAssertEqual(noFunctionInBody.status, .badRequest)
        XCTAssertNotNil(noFunctionInBody.json["error"] as? String)
    }

    func testJobRoutesNeedAnOpenProject() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        let file = try writeFile("lone.c", "int f(void) {\n    return 1;\n}\n")

        let requests: [(path: String, body: [String: Any])] = [
            ("api/variable-flow", ["path": file.path, "location": 0, "variable": "x"]),
            ("api/reachability", ["path": file.path, "function": "f"]),
            ("api/class-usage", ["className": "Widget"]),
            ("api/backtrace", ["text": "at f (lone.c:2)"]),
            ("api/entry-points/start", [:]),
        ]
        for request in requests {
            let reply = try await send(app, .POST, request.path, json: request.body)
            XCTAssertEqual(reply.status, .badRequest, request.path)
            XCTAssertNotNil(reply.json["error"] as? String, request.path)
            XCTAssertNil(reply.json["jobId"], request.path)
        }
    }

    // MARK: - Flow and complexity

    func testFlowChartsAnIfInsideAWhileLoop() async throws {
        let file = try writeFile("count.c", """
        int classify(int n) {
            int total = 0;
            while (n > 0) {
                if (n % 2 == 0) {
                    total += 2;
                } else {
                    total += 1;
                }
                n--;
            }
            return total;
        }
        """)
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let reply = try await send(app, .GET, "api/flow?path=\(query(file.path))&function=classify")
        XCTAssertEqual(reply.status, .ok)
        let dto = try KarmaJSON.decoder.decode(FlowService.FlowDTO.self, from: reply.body)
        XCTAssertEqual(dto.functionName, "classify")
        XCTAssertEqual(dto.complexity, 3)
        let chart = try XCTUnwrap(dto.chart)
        XCTAssertEqual(chart.nodes.filter { $0.kind == "decision" }.count, 2)
        XCTAssertTrue(chart.edges.contains { $0.isBackEdge }, "the while loop must have a back edge")
    }

    func testComplexityOfOneFileListsEveryFunctionInOrder() async throws {
        let file = try writeFile("two.c", """
        int one(int x) {
            if (x) { return 1; }
            return 0;
        }
        int two(void) {
            return 2;
        }
        """)
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let reply = try await send(app, .GET, "api/complexity?path=\(query(file.path))")
        XCTAssertEqual(reply.status, .ok)
        let dto = try KarmaJSON.decoder.decode(FlowService.ComplexityDTO.self, from: reply.body)
        XCTAssertEqual(dto.points.map(\.name), ["one", "two"])
        XCTAssertEqual(dto.points.map(\.complexity), [2, 1])
    }

    // MARK: - Class usage (job round trip)

    func testClassUsageJobCompletesWithEverySite() async throws {
        _ = try writeFile("Main.java", """
        public class Main {
            public static void main(String[] args) {
                Widget first = new Widget(1);
                Widget second = new Widget(2);
            }
        }
        """)
        _ = try KarmaWorkspace.shared.open(root: scratch.path)
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let reply = try await send(app, .POST, "api/class-usage", json: ["className": "Widget"])
        XCTAssertEqual(reply.status, .ok)
        let jobID = try XCTUnwrap(reply.json["jobId"] as? String)

        let job = try await finishedJob(jobID)
        XCTAssertEqual(job.status, "completed")
        let dto = try KarmaJSON.decoder.decode(FlowService.ClassUsageDTO.self,
                                               from: try XCTUnwrap(job.resultJSON))
        XCTAssertEqual(dto.className, "Widget")
        XCTAssertEqual(dto.sites.count, 2)
        XCTAssertEqual(dto.sites.map(\.line).sorted(), [3, 4])
        XCTAssertNotNil(dto.graph)
    }

    // MARK: - Debugger simulation

    func testSimulationLoadStepParameterAndResetRoundTrip() async throws {
        let file = try writeFile("add.c", """
        int add(int a, int b) {
            int total = a + b;
            return total;
        }
        """)
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let loadReply = try await send(app, .POST, "api/sim/load",
                                       json: ["path": file.path, "function": "add"])
        XCTAssertEqual(loadReply.status, .ok)
        let loaded = try KarmaJSON.decoder.decode(SimDebugService.SimStateDTO.self, from: loadReply.body)
        XCTAssertTrue(loaded.loaded)
        XCTAssertEqual(loaded.functionName, "add")
        XCTAssertEqual(loaded.parameters.map(\.name), ["a", "b"])
        XCTAssertEqual(loaded.stepCount, 0)

        let stepReply = try await send(app, .POST, "api/sim/step", json: ["mode": "over"])
        XCTAssertEqual(stepReply.status, .ok)
        let stepped = try KarmaJSON.decoder.decode(SimDebugService.SimStateDTO.self, from: stepReply.body)
        XCTAssertEqual(stepped.stepCount, 1)

        let paramReply = try await send(app, .PUT, "api/sim/param", json: ["index": 0, "text": "5"])
        XCTAssertEqual(paramReply.status, .ok)

        let resetReply = try await send(app, .POST, "api/sim/reset")
        XCTAssertEqual(resetReply.status, .ok)
        let reset = try KarmaJSON.decoder.decode(SimDebugService.SimStateDTO.self, from: resetReply.body)
        XCTAssertEqual(reset.stepCount, 0)

        let badMode = try await send(app, .POST, "api/sim/step", json: ["mode": "sideways"])
        XCTAssertEqual(badMode.status, .badRequest)
        XCTAssertNotNil(badMode.json["error"] as? String)
    }
}
#endif
