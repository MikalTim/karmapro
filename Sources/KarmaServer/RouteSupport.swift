// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// Shared helpers for the route files. Every route file registers its routes on the `/api` group with a
/// `registerXRoutes(_ api: RoutesBuilder)` function; `Configure.swift` calls them.
extension Request {
    /// Runs blocking service work on a worker thread, so a long call never holds up the event loop. A
    /// `KarmaServiceError` the work throws is turned into its HTTP status by `KarmaErrorMiddleware`.
    func service<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await application.threadPool.runIfActive(eventLoop: eventLoop, work).get()
    }

    /// The JSON body decoded with `KarmaJSON.decoder`; an empty or malformed body is a 400.
    func jsonBody<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        guard let buffer = body.data, buffer.readableBytes > 0 else {
            throw Abort(.badRequest, reason: "The request needs a JSON body.")
        }
        do {
            return try KarmaJSON.decoder.decode(T.self, from: Data(buffer.readableBytesView))
        } catch {
            throw Abort(.badRequest, reason: "The request body is not valid: \(error.localizedDescription)")
        }
    }

    /// The raw request body (an uploaded file).
    func uploadedData() throws -> Data {
        guard let buffer = body.data, buffer.readableBytes > 0 else {
            throw Abort(.badRequest, reason: "The request needs a file in its body.")
        }
        return Data(buffer.readableBytesView)
    }

    /// The `?filename=` an upload carries.
    var uploadedFileName: String {
        query[String.self, at: "filename"] ?? "upload"
    }

    /// A required query parameter; a missing one is a 400.
    func requiredQuery(_ name: String) throws -> String {
        guard let value = query[String.self, at: name] else {
            throw Abort(.badRequest, reason: "The query parameter \"\(name)\" is required.")
        }
        return value
    }

    /// A boolean query parameter written `1`/`0` or `true`/`false`.
    func flag(_ name: String, default fallback: Bool = false) -> Bool {
        guard let raw = query[String.self, at: name]?.lowercased() else { return fallback }
        return raw == "1" || raw == "true"
    }

    /// The integer in `name`; a missing or non-numeric value is a 400.
    func requiredInt(_ name: String) throws -> Int {
        guard let value = query[Int.self, at: name] else {
            throw Abort(.badRequest, reason: "The query parameter \"\(name)\" must be a number.")
        }
        return value
    }
}

/// `{"jobId": "<id>"}`, what every endpoint that starts a job returns.
func jobStartedResponse(_ id: String) -> Response {
    struct Body: Encodable { let jobId: String }
    return jsonResponse(Body(jobId: id))
}

/// `{"ok": true}`.
func okResponse() -> Response {
    struct Body: Encodable { let ok = true }
    return jsonResponse(Body())
}

/// A file download named like the AppKit save panel's `nameFieldStringValue`.
func downloadResponse(fileName: String, data: Data, contentType: String = "application/octet-stream") -> Response {
    var headers = HTTPHeaders()
    headers.replaceOrAdd(name: .contentType, value: contentType)
    let safeName = fileName.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\n", with: " ")
    headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"\(safeName)\"")
    return Response(status: .ok, headers: headers, body: .init(data: data))
}

/// A text body with an explicit content type.
func textResponse(_ text: String, contentType: String, status: HTTPStatus = .ok) -> Response {
    var headers = HTTPHeaders()
    headers.replaceOrAdd(name: .contentType, value: contentType)
    return Response(status: status, headers: headers, body: .init(string: text))
}
