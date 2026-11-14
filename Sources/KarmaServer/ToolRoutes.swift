// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The tool windows: Search in Files, Scan Project's Packages, Licensing, Notes and Help.
///
///  - `POST /api/search` `{term, language?}` -> `{jobId}`. The job result is `SearchService.ResultDTO`.
///  - `POST /api/packages/detect` -> `{jobId}`. The job result is `PackageScanService.StateDTO`.
///  - `POST /api/packages/scan` `{apiSource}` -> `{jobId}`. `apiSource` is an `ApiSourceDTO.id`; the job result is `StateDTO`.
///  - `GET /api/packages` -> `StateDTO`.
///  - `POST /api/packages/ignore` `{key, ignored}` -> `StateDTO`.
///  - `POST /api/packages/sort` `{key?, ascending?}` -> `StateDTO`. Not in the parity table, which lists none for the
///    table's sort descriptors; it mirrors `POST /api/scan/sort`. A missing `key` restores the default order.
///  - `GET /api/packages/export` -> the SARIF file `KarmaPro-packages.sarif.json` (400 when no rows are listed).
///  - `POST /api/licenses` -> `{jobId}`. The job result is `LicenseService.ReportDTO`.
///  - `GET /api/notes` -> `NotesService.ListDTO`.
///  - `GET /api/notes/export` -> the `.codenotes` file, named `<project>-notes.codenotes`.
///  - `POST /api/notes/import` (raw body, `?filename=`) -> `NotesService.ImportResultDTO` (400 for an empty body).
///  - `POST /api/notes/import-url` `{url}` -> `{jobId}`. The job result is `NotesService.ImportResultDTO`.
///  - `GET /api/help` -> the help page, `text/html`.
func registerToolRoutes(_ api: RoutesBuilder) {
    struct SearchRequest: Decodable {
        let term: String
        let language: String?
    }
    struct PackageScanRequest: Decodable {
        let apiSource: String?
    }
    struct PackageIgnoreRequest: Decodable {
        let key: String
        let ignored: Bool
    }
    struct PackageSortRequest: Decodable {
        let key: String?
        let ascending: Bool?
    }
    struct ImportURLRequest: Decodable {
        let url: String
    }

    api.post("search") { req async throws -> Response in
        let request = try req.jsonBody(SearchRequest.self)
        let id = try await req.service { try SearchService.search(term: request.term, language: request.language) }
        return jobStartedResponse(id)
    }

    api.post("packages", "detect") { req async throws -> Response in
        jobStartedResponse(try await req.service { try PackageScanService.detect() })
    }
    api.post("packages", "scan") { req async throws -> Response in
        let request = try req.jsonBody(PackageScanRequest.self)
        let id = try await req.service { try PackageScanService.scan(apiSource: request.apiSource) }
        return jobStartedResponse(id)
    }
    api.get("packages") { req async throws -> Response in
        jsonResponse(try await req.service { PackageScanService.state() })
    }
    api.post("packages", "ignore") { req async throws -> Response in
        let request = try req.jsonBody(PackageIgnoreRequest.self)
        return jsonResponse(try await req.service { PackageScanService.setIgnored(key: request.key, ignored: request.ignored) })
    }
    api.post("packages", "sort") { req async throws -> Response in
        let request = try req.jsonBody(PackageSortRequest.self)
        return jsonResponse(try await req.service {
            PackageScanService.sort(key: request.key, ascending: request.ascending ?? true)
        })
    }
    api.get("packages", "export") { req async throws -> Response in
        let file = try await req.service { try PackageScanService.export() }
        return downloadResponse(fileName: file.fileName, data: file.data, contentType: "application/json")
    }

    api.post("licenses") { req async throws -> Response in
        jobStartedResponse(try await req.service { LicenseService.report() })
    }

    api.get("notes") { req async throws -> Response in
        jsonResponse(try await req.service { NotesService.list() })
    }
    api.get("notes", "export") { req async throws -> Response in
        let file = try await req.service { try NotesService.export() }
        return downloadResponse(fileName: file.fileName, data: file.data)
    }
    api.post("notes", "import") { req async throws -> Response in
        let data = try req.uploadedData()
        return jsonResponse(try await req.service { NotesService.importNotes(data: data) })
    }
    api.post("notes", "import-url") { req async throws -> Response in
        let request = try req.jsonBody(ImportURLRequest.self)
        return jobStartedResponse(try await req.service { try NotesService.importNotes(urlString: request.url) })
    }

    api.get("help") { req async throws -> Response in
        textResponse(try await req.service { HelpService.html() }, contentType: "text/html; charset=utf-8")
    }
}
