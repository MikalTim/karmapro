// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The private wiki (the list, editor and import windows, row 22 of the parity map).
///
///  - `GET /api/wiki?query=` -> `WikiService.WikiListDTO`: the pages matching the search (title or body), newest update first.
///  - `POST /api/wiki` `{title, slug?}` -> `WikiService.WikiPageDTO` (400 when a page with that slug already exists).
///  - `GET /api/wiki/resolve?target=` -> `{slug}`: the slug a link target refers to, `{slug: null}` when there is no such page.
///  - `GET /api/wiki/:slug` -> `WikiService.WikiPageDetailDTO` `{info, document}` (404 when the page no longer exists).
///  - `PUT /api/wiki/:slug` `{title, document}` (`document` is a `WikiDocument`) -> `{ok}` (404 when the page no longer exists).
///  - `POST /api/wiki/:slug/rename` `{title}` -> `WikiService.WikiPageDTO` under its new slug. A blank or unchanged title changes nothing.
///  - `DELETE /api/wiki/:slug` -> `{ok}` (404 when the page no longer exists).
///  - `POST /api/wiki/backup` `{password?}` -> the download `KarmaProWiki.karmawiki` (needs the `zip` and `unzip` tools).
///    An empty body is a plain backup; a blank password is 400.
///  - `POST /api/wiki/import?password=` (raw file body, `?filename=`) -> `WikiService.WikiImportSessionDTO`
///    `{importID, conflicts, conflictTitles}`. The upload waits ten minutes under `importID`. An encrypted file without
///    a password -> 422 `{error, needsPassword: true}`; a wrong password or an unreadable file -> 400 `{error}`.
///  - `POST /api/wiki/import/:importID/resolve` `{decisions: {slug: "overwrite"|"rename"|"skip"}}` -> `WikiService.WikiImportResultDTO`.
///    A slug without a decision is skipped. An unknown or expired `importID` -> 404 `{error}`.
func registerWikiRoutes(_ api: RoutesBuilder) {
    struct CreateRequest: Decodable {
        let title: String
        let slug: String?
    }
    struct SaveRequest: Decodable {
        let title: String
        let document: WikiDocument
    }
    struct RenameRequest: Decodable { let title: String }
    struct ResolveRequest: Decodable { let decisions: [String: String] }

    api.get("wiki") { req async throws -> Response in
        let query = req.query[String.self, at: "query"] ?? ""
        return jsonResponse(try await req.service { WikiService.list(query: query) })
    }
    api.post("wiki") { req async throws -> Response in
        let request = try req.jsonBody(CreateRequest.self)
        return jsonResponse(try await req.service { try WikiService.create(title: request.title, slug: request.slug) })
    }

    // The constant paths are registered beside the `:slug` ones; the router prefers them, and
    // `BugWikiRoutesTests` checks that `resolve` is not read as a page slug.
    api.get("wiki", "resolve") { req async throws -> Response in
        let target = try req.requiredQuery("target")
        let slug = try await req.service { WikiService.resolve(target: target) }
        return jsonResponse(ResolveBody(slug: slug))
    }
    api.post("wiki", "backup") { req async throws -> Response in
        let password = try backupPassword(from: req)
        let file = try await req.service { try WikiService.backup(password: password) }
        return downloadResponse(fileName: file.fileName, data: file.data)
    }
    api.post("wiki", "import") { req async throws -> Response in
        let data = try req.uploadedData()
        let password = req.query[String.self, at: "password"]
        do {
            return jsonResponse(try await req.service { try WikiService.beginImport(data: data, password: password) })
        } catch {
            return try importFailureResponse(error)
        }
    }
    api.post("wiki", "import", ":importID", "resolve") { req async throws -> Response in
        let importID = try requiredParameter(req, "importID")
        let request = try req.jsonBody(ResolveRequest.self)
        return jsonResponse(try await req.service {
            try WikiService.finishImport(importID: importID, decisions: request.decisions)
        })
    }

    api.get("wiki", ":slug") { req async throws -> Response in
        let slug = try requiredParameter(req, "slug")
        return jsonResponse(try await req.service { try WikiService.page(slug: slug) })
    }
    api.put("wiki", ":slug") { req async throws -> Response in
        let slug = try requiredParameter(req, "slug")
        let request = try req.jsonBody(SaveRequest.self)
        try await req.service { try WikiService.save(slug: slug, title: request.title, document: request.document) }
        return okResponse()
    }
    api.post("wiki", ":slug", "rename") { req async throws -> Response in
        let slug = try requiredParameter(req, "slug")
        let request = try req.jsonBody(RenameRequest.self)
        return jsonResponse(try await req.service { try WikiService.rename(slug: slug, title: request.title) })
    }
    api.delete("wiki", ":slug") { req async throws -> Response in
        let slug = try requiredParameter(req, "slug")
        try await req.service { try WikiService.delete(slug: slug) }
        return okResponse()
    }
}

/// `{"slug": "<slug>"}`, or `{"slug": null}` when the link target has no page.
private struct ResolveBody: Encodable {
    let slug: String?

    enum CodingKeys: String, CodingKey { case slug }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
    }
}
