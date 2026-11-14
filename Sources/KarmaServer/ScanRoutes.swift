// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The Security Scan window. One scan state exists; changes are announced with the `scan.changed` event.
///
///  - `GET /api/scan` -> `SecurityScanService.StateDTO`.
///  - `GET /api/scan/prompt` -> `ScanPromptDTO`, the "Also run an AI scan?" question (400 when no project is open).
///  - `POST /api/scan/start` `{wantsAI, ignoreAICache?}` -> `{jobId}`.
///  - `POST /api/scan/rescan` -> `{jobId}`.
///  - `POST /api/scan/cancel` -> `{ok}`.
///  - `POST /api/scan/sort` `{keys: [{key, ascending}]}` -> `StateDTO`, the table's sort descriptors.
///  - `POST /api/scan/ignore` `{key}` -> `StateDTO`: "Ignore issue" (`ignored` is accepted and must be true).
///  - `GET /api/scan/triage-prompt` -> `ScanPromptDTO`, the Triage (AI) confirmation.
///  - `POST /api/scan/triage` `{action: "start" | "cancel"}` -> `{jobId}` for start, `StateDTO` for cancel.
///  - `GET /api/scan/export` -> the SARIF file `KarmaPro-scan.sarif.json` (400 when there are no findings).
func registerScanRoutes(_ api: RoutesBuilder) {
    struct StartRequest: Decodable {
        let wantsAI: Bool
        let ignoreAICache: Bool?
    }
    struct SortRequest: Decodable { let keys: [SecurityScanService.SortKeyDTO] }
    struct IgnoreRequest: Decodable {
        let key: String
        let ignored: Bool?
    }
    struct TriageRequest: Decodable { let action: String }

    let scan = SecurityScanService.shared

    api.get("scan") { req async throws -> Response in
        jsonResponse(try await req.service { scan.state() })
    }
    api.get("scan", "prompt") { req async throws -> Response in
        jsonResponse(try await req.service { try scan.scanPrompt() })
    }
    api.post("scan", "start") { req async throws -> Response in
        let request = try req.jsonBody(StartRequest.self)
        let id = try await req.service {
            try scan.start(wantsAI: request.wantsAI, ignoreAICache: request.ignoreAICache ?? false)
        }
        return jobStartedResponse(id)
    }
    api.post("scan", "rescan") { req async throws -> Response in
        jobStartedResponse(try await req.service { try scan.rescan() })
    }
    api.post("scan", "cancel") { req async throws -> Response in
        try await req.service { scan.cancel() }
        return okResponse()
    }
    api.post("scan", "sort") { req async throws -> Response in
        let request = try req.jsonBody(SortRequest.self)
        return jsonResponse(try await req.service {
            scan.setSort(request.keys)
            return scan.state()
        })
    }
    api.post("scan", "ignore") { req async throws -> Response in
        let request = try req.jsonBody(IgnoreRequest.self)
        guard request.ignored ?? true else {
            throw Abort(.badRequest, reason: "An ignored finding stays ignored; \"ignored\" must be true.")
        }
        return jsonResponse(try await req.service {
            try scan.ignore(key: request.key)
            return scan.state()
        })
    }
    api.get("scan", "triage-prompt") { req async throws -> Response in
        jsonResponse(try await req.service { scan.triagePrompt() })
    }
    api.post("scan", "triage") { req async throws -> Response in
        let request = try req.jsonBody(TriageRequest.self)
        switch request.action {
        case "start":
            return jobStartedResponse(try await req.service { try scan.startTriage() })
        case "cancel":
            return jsonResponse(try await req.service {
                scan.cancelTriage()
                return scan.state()
            })
        default:
            throw Abort(.badRequest, reason: "The triage action must be \"start\" or \"cancel\".")
        }
    }
    api.get("scan", "export") { req async throws -> Response in
        let file = try await req.service { try scan.export() }
        return downloadResponse(fileName: file.fileName, data: file.data, contentType: "application/json")
    }
}
