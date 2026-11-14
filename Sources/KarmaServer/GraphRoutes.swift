// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The graph routes: the flow panel, data flow, variable flow, reachability, complexity distribution,
/// backtrace analyser and class usage (`FlowService`), the entry-point finder (`EntryPointsService`) and the
/// debugger simulation (`SimDebugService`).
///
/// Synchronous services answer with their DTO. Services that run as jobs answer `{"jobId": "<id>"}`; the
/// result arrives as the job's `result` (`GET /api/jobs/:id`), which is the DTO named in each route below.
func registerGraphRoutes(_ api: RoutesBuilder) {

    // MARK: - Flow panel and data flow

    /// `GET /api/flow?path=&function=`: complexity, callees and flowchart of one function.
    /// Query: `path` (absolute file path), `function`. Response: `FlowService.FlowDTO`.
    /// The service reads any file, so this route needs no open project.
    api.get("flow") { req async throws -> Response in
        let path = try nonEmpty(req.requiredQuery("path"), "path")
        let function = try nonEmpty(req.requiredQuery("function"), "function")
        let dto = try await req.service { try FlowService.flow(path: path, function: function) }
        return jsonResponse(dto)
    }

    /// `GET /api/dataflow?path=&function=`: the direct callers and callees of one function within its file.
    /// Query: `path`, `function`. Response: `FlowService.DataFlowDTO`.
    api.get("dataflow") { req async throws -> Response in
        let path = try nonEmpty(req.requiredQuery("path"), "path")
        let function = try nonEmpty(req.requiredQuery("function"), "function")
        let dto = try await req.service { try FlowService.dataFlow(path: path, function: function) }
        return jsonResponse(dto)
    }

    // MARK: - Variable flow, reachability (project jobs)

    /// `POST /api/variable-flow {path, location, variable}`: traces `variable`, used at the UTF-16 offset
    /// `location` of `path`, across the open project. Needs an open project (400 otherwise).
    /// Response: `{"jobId"}`. The job result is `FlowService.VariableFlowDTO`.
    api.post("variable-flow") { req async throws -> Response in
        let body = try req.jsonBody(GraphVariableFlow.self)
        let path = try nonEmpty(body.path, "path")
        let variable = try nonEmpty(body.variable, "variable")
        guard body.location >= 0 else {
            throw Abort(.badRequest, reason: "\"location\" must not be negative.")
        }
        let id = try await req.service {
            try FlowService.variableFlow(path: path, location: body.location, variable: variable)
        }
        return jobStartedResponse(id)
    }

    /// `POST /api/reachability {path, function}`: the project-wide caller chain of `function` and its direct
    /// callees. Needs an open project (400 otherwise). Response: `{"jobId"}`. The job result is
    /// `FlowService.ReachabilityDTO`.
    api.post("reachability") { req async throws -> Response in
        let body = try req.jsonBody(GraphPathFunction.self)
        let path = try nonEmpty(body.path, "path")
        let function = try nonEmpty(body.function, "function")
        let id = try await req.service { try FlowService.reachability(path: path, function: function) }
        return jobStartedResponse(id)
    }

    // MARK: - Complexity distribution

    /// `GET /api/complexity?path=`: every function of one file, answered at once with `FlowService.ComplexityDTO`.
    /// Without `path` it plots the whole open project instead. That scan runs as a job, so the response is
    /// `{"jobId"}` and the job result is `FlowService.ComplexityDTO`. Without `path` a project must be open (400
    /// otherwise). An empty `path` is a 400.
    api.get("complexity") { req async throws -> Response in
        if let path = req.query[String.self, at: "path"] {
            let file = try nonEmpty(path, "path")
            let dto = try await req.service { try FlowService.complexity(path: file) }
            return jsonResponse(dto)
        }
        let id = try await req.service { try FlowService.complexityJob(path: nil) }
        return jobStartedResponse(id)
    }

    // MARK: - Backtrace analyser

    /// `POST /api/backtrace {text}`: parses a pasted stacktrace and resolves each frame inside the open project.
    /// Needs an open project (400 otherwise). Response: `FlowService.BacktraceDTO`.
    api.post("backtrace") { req async throws -> Response in
        let body = try req.jsonBody(GraphText.self)
        let dto = try await req.service { try FlowService.backtrace(text: body.text) }
        return jsonResponse(dto)
    }

    // MARK: - Class usage (project job)

    /// `POST /api/class-usage {className}`: every `new ClassName(` in the open project's Java and C# files.
    /// Needs an open project (400 otherwise). Response: `{"jobId"}`. The job result is `FlowService.ClassUsageDTO`.
    api.post("class-usage") { req async throws -> Response in
        let body = try req.jsonBody(GraphClassName.self)
        let className = try nonEmpty(body.className, "className")
        let id = try await req.service { try FlowService.classUsage(className: className) }
        return jobStartedResponse(id)
    }

    // MARK: - Entry points

    /// `GET /api/entry-points`: the current entry-point result set, for a page reload. Response:
    /// `EntryPointsService.EntryPointsStateDTO`. This route is not in the parity table; it only reads the state.
    api.get("entry-points") { req async throws -> Response in
        let dto = try await req.service { EntryPointsService.shared.state() }
        return jsonResponse(dto)
    }

    /// `POST /api/entry-points/start`: finds the primary entry points of the open project. Needs an open project
    /// (400 otherwise). Response: `{"jobId"}`. The job result is `EntryPointsService.EntryPointsStateDTO`.
    api.post("entry-points", "start") { req async throws -> Response in
        let id = try await req.service { try EntryPointsService.shared.start() }
        return jobStartedResponse(id)
    }

    /// `POST /api/entry-points/indirect {on}`: turns the indirect tier on or off; the first switch on collects it.
    /// Needs an open project (400 otherwise). Response: `{"jobId"}`. The job result is
    /// `EntryPointsService.EntryPointsStateDTO`.
    api.post("entry-points", "indirect") { req async throws -> Response in
        let body = try req.jsonBody(GraphOn.self)
        let id = try await req.service { try EntryPointsService.shared.setIndirect(body.on) }
        return jobStartedResponse(id)
    }

    /// `POST /api/entry-points/trace {siteID}`: traces the flow of one entry point (its `EntrySiteDTO.id`).
    /// An unknown id is a 404. Response: `{"jobId"}`. The job result is `EntryPointsService.EntryTraceDTO`.
    api.post("entry-points", "trace") { req async throws -> Response in
        let body = try req.jsonBody(GraphSite.self)
        let siteID = try nonEmpty(body.siteID, "siteID")
        let id = try await req.service { try EntryPointsService.shared.trace(siteID: siteID) }
        return jobStartedResponse(id)
    }

    // MARK: - Debugger simulation

    /// `GET /api/sim`: the current simulation. Response: `SimDebugService.SimStateDTO`. Not loaded until a
    /// function is loaded.
    api.get("sim") { req async throws -> Response in
        let dto = try await req.service { SimDebugService.shared.state() }
        return jsonResponse(dto)
    }

    /// `POST /api/sim/load {path, function}`: loads `function` from the file at `path` and starts at its first
    /// line. An unknown function is a 404. Response: `SimDebugService.SimStateDTO`.
    api.post("sim", "load") { req async throws -> Response in
        let body = try req.jsonBody(GraphPathFunction.self)
        let path = try nonEmpty(body.path, "path")
        let function = try nonEmpty(body.function, "function")
        let dto = try await req.service { try SimDebugService.shared.load(path: path, function: function) }
        return jsonResponse(dto)
    }

    /// `POST /api/sim/step {mode}`: one step, `mode` = `"over"`, `"into"` or `"back"`. Needs a loaded function
    /// (404 otherwise). An unknown mode is a 400. Response: `SimDebugService.SimStateDTO`.
    api.post("sim", "step") { req async throws -> Response in
        let body = try req.jsonBody(GraphStep.self)
        let dto = try await req.service { try SimDebugService.shared.step(mode: body.mode) }
        return jsonResponse(dto)
    }

    /// `POST /api/sim/reset`: restores the parameter seeds and starts again at the first line.
    /// Response: `SimDebugService.SimStateDTO`.
    api.post("sim", "reset") { req async throws -> Response in
        let dto = try await req.service { SimDebugService.shared.reset() }
        return jsonResponse(dto)
    }

    /// `POST /api/sim/play`: steps over until the simulation finishes or the per-call step limit is reached.
    /// Needs a loaded function (404 otherwise). Response: `SimDebugService.SimStateDTO`.
    api.post("sim", "play") { req async throws -> Response in
        let dto = try await req.service { try SimDebugService.shared.play() }
        return jsonResponse(dto)
    }

    /// `PUT /api/sim/param {index, text}`: sets parameter `index` from `text`; it takes effect at the next reset.
    /// Needs a loaded function (404 otherwise). Response: `SimDebugService.SimStateDTO`.
    api.put("sim", "param") { req async throws -> Response in
        let body = try req.jsonBody(GraphParameter.self)
        let dto = try await req.service { try SimDebugService.shared.setParameter(index: body.index, text: body.text) }
        return jsonResponse(dto)
    }

    /// `POST /api/sim/frame {index}`: chooses the call-stack frame whose variables the watch table shows.
    /// This route is not in the parity table; the stack table needs it to change the selection.
    /// Needs a loaded function (404 otherwise). Response: `SimDebugService.SimStateDTO`.
    api.post("sim", "frame") { req async throws -> Response in
        let body = try req.jsonBody(GraphFrame.self)
        let dto = try await req.service { try SimDebugService.shared.selectFrame(index: body.index) }
        return jsonResponse(dto)
    }
}

/// A text value that must not be empty; an empty one is a 400, as a missing one is.
private func nonEmpty(_ value: String, _ name: String) throws -> String {
    guard !value.isEmpty else {
        throw Abort(.badRequest, reason: "\"\(name)\" must not be empty.")
    }
    return value
}

private struct GraphPathFunction: Decodable {
    let path: String
    let function: String
}

private struct GraphVariableFlow: Decodable {
    let path: String
    let location: Int
    let variable: String
}

private struct GraphText: Decodable {
    let text: String
}

private struct GraphClassName: Decodable {
    let className: String
}

private struct GraphOn: Decodable {
    let on: Bool
}

private struct GraphSite: Decodable {
    let siteID: String
}

private struct GraphStep: Decodable {
    let mode: String
}

private struct GraphParameter: Decodable {
    let index: Int
    let text: String
}

private struct GraphFrame: Decodable {
    let index: Int
}
