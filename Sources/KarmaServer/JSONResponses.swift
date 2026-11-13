// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// A response whose body is already-encoded JSON.
func jsonResponse(_ data: Data, status: HTTPStatus = .ok) -> Response {
    var headers = HTTPHeaders()
    headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
    return Response(status: status, headers: headers, body: .init(data: data))
}

/// A response whose body is `value` encoded with `KarmaJSON`.
func jsonResponse<T: Encodable>(_ value: T, status: HTTPStatus = .ok) -> Response {
    jsonResponse(KarmaJSON.data(value), status: status)
}

/// `{"error": "<message>"}` with the given status.
func jsonErrorResponse(_ message: String, status: HTTPStatus) -> Response {
    struct Body: Encodable { let error: String }
    return jsonResponse(Body(error: message), status: status)
}

/// Turns thrown errors into `{"error": …}` responses and marks every API
/// response as uncacheable.
///
///   KarmaServiceError.noProject / .notADirectory / .invalid  → 400
///   KarmaServiceError.notFound                               → 404
///   KarmaServiceError.busy                                   → 409
///   Abort                                                    → its own status
///   anything else                                            → 500
struct KarmaErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let response: Response
        do {
            response = try await next.respond(to: request)
        } catch let error as KarmaServiceError {
            switch error {
            case .noProject, .notADirectory, .invalid:
                response = jsonErrorResponse(error.localizedDescription, status: .badRequest)
            case .notFound:
                response = jsonErrorResponse(error.localizedDescription, status: .notFound)
            case .busy:
                response = jsonErrorResponse(error.localizedDescription, status: .conflict)
            }
        } catch let abort as AbortError {
            response = jsonErrorResponse(abort.reason, status: abort.status)
        } catch {
            response = jsonErrorResponse(error.localizedDescription, status: .internalServerError)
        }
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return response
    }
}
