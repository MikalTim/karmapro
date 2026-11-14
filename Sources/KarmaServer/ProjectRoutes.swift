// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The main window's project features.
///
///  - `POST /api/project/open` `{path}` -> `{jobId}`: opens the folder and starts the index build job.
///  - `POST /api/project/close` -> `{ok}`: closes the project.
///  - `GET /api/project` -> `ProjectInfoDTO`.
///  - `GET /api/languages` -> `[String]`, the language popup's names ("All Languages" first).
///  - `GET /api/project/tree?language=&query=` -> `ProjectTreeDTO`.
func registerProjectRoutes(_ api: RoutesBuilder) {
    struct OpenRequest: Decodable { let path: String }

    api.post("project", "open") { req async throws -> Response in
        let request = try req.jsonBody(OpenRequest.self)
        let id = try await req.service { try ProjectService.open(path: request.path) }
        return jobStartedResponse(id)
    }
    api.post("project", "close") { req async throws -> Response in
        try await req.service { KarmaWorkspace.shared.close() }
        return okResponse()
    }
    api.get("project") { req async throws -> Response in
        jsonResponse(try await req.service { ProjectService.info() })
    }
    api.get("languages") { req async throws -> Response in
        jsonResponse(try await req.service { ProjectService.languages() })
    }
    api.get("project", "tree") { req async throws -> Response in
        let language = req.query[String.self, at: "language"]
        let query = req.query[String.self, at: "query"]
        return jsonResponse(try await req.service { try ProjectService.tree(language: language, query: query) })
    }
}
