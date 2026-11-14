// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The security bug tracker (the list and editor windows, row 21 of the parity map).
///
///  - `GET /api/bugs?query=` -> `BugService.BugListDTO`: the reports matching the search, newest first.
///  - `GET /api/bugs/choices` -> `BugService.BugChoicesDTO`: the editor's popup values, preset titles and new-report defaults.
///  - `POST /api/bugs` `BugService.BugInputDTO` -> `BugService.BugDTO` (400 when the title is blank or a choice is unknown).
///  - `PUT /api/bugs/:id` `BugService.BugInputDTO` -> `BugService.BugDTO` (404 when the report no longer exists).
///  - `DELETE /api/bugs/:id` -> `{ok}` (404 when the report no longer exists).
///  - `POST /api/bugs/backup` `{password?}` -> the download `KarmaProBugBackup.karmapro`. An empty body is a plain
///    backup; a blank password is 400.
///  - `POST /api/bugs/import?password=` (raw file body, `?filename=`) -> `BugService.BugImportResultDTO`. An encrypted
///    file without a password -> 422 `{error, needsPassword: true}`; a wrong password or an unreadable file -> 400 `{error}`.
func registerBugRoutes(_ api: RoutesBuilder) {
    api.get("bugs") { req async throws -> Response in
        let query = req.query[String.self, at: "query"] ?? ""
        return jsonResponse(try await req.service { BugService.list(query: query) })
    }
    api.get("bugs", "choices") { req async throws -> Response in
        jsonResponse(BugService.choices())
    }
    api.post("bugs") { req async throws -> Response in
        let input = try req.jsonBody(BugService.BugInputDTO.self)
        return jsonResponse(try await req.service { try BugService.create(input) })
    }
    api.put("bugs", ":id") { req async throws -> Response in
        let id = try requiredParameter(req, "id")
        let input = try req.jsonBody(BugService.BugInputDTO.self)
        return jsonResponse(try await req.service { try BugService.update(id: id, input) })
    }
    api.delete("bugs", ":id") { req async throws -> Response in
        let id = try requiredParameter(req, "id")
        try await req.service { try BugService.delete(id: id) }
        return okResponse()
    }
    api.post("bugs", "backup") { req async throws -> Response in
        let password = try backupPassword(from: req)
        let file = try await req.service { try BugService.backup(password: password) }
        return downloadResponse(fileName: file.fileName, data: file.data)
    }
    api.post("bugs", "import") { req async throws -> Response in
        let data = try req.uploadedData()
        let password = req.query[String.self, at: "password"]
        do {
            return jsonResponse(try await req.service { try BugService.importBackup(data: data, password: password) })
        } catch {
            return try importFailureResponse(error)
        }
    }
}

/// The body of the 422 answer to an encrypted upload that came without a password.
private struct NeedsPasswordBody: Encodable {
    let error: String
    let needsPassword: Bool
}

/// The answer to an upload an import refused. An encrypted file without a password is 422 with
/// `needsPassword: true`; every other refusal (a wrong password, an unreadable file) is 400 with the
/// service's message. Errors that are already a `KarmaServiceError` keep their own status.
func importFailureResponse(_ error: Error) throws -> Response {
    if let serviceError = error as? KarmaServiceError {
        throw serviceError
    }
    let needsPassword: Bool
    switch error {
    case BugService.ImportError.needsPassword, WikiService.ImportError.needsPassword:
        needsPassword = true
    default:
        needsPassword = false
    }
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    if needsPassword {
        return jsonResponse(NeedsPasswordBody(error: message, needsPassword: true), status: .unprocessableEntity)
    }
    throw Abort(.badRequest, reason: message)
}

/// The `:name` path parameter; a missing one is a 400.
func requiredParameter(_ req: Request, _ name: String) throws -> String {
    guard let value = req.parameters.get(name), !value.isEmpty else {
        throw Abort(.badRequest, reason: "The path parameter \"\(name)\" is required.")
    }
    return value
}

/// The optional `{password}` of a backup request. An empty body means no password (a plain backup).
func backupPassword(from req: Request) throws -> String? {
    struct BackupRequest: Decodable { let password: String? }
    guard let buffer = req.body.data, buffer.readableBytes > 0 else { return nil }
    return try req.jsonBody(BackupRequest.self).password
}
