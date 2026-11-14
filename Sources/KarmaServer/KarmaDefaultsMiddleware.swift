// by cipher.org.uk
import Foundation
import Vapor

/// Writes `UserDefaults` to disk after every API call that can change a setting.
///
/// On Linux `UserDefaults` keeps its values in memory until it is told to write them, so a server stopped
/// with Ctrl+C or `kill` would lose ignored findings, the MCP token, AI keys and the update preference.
/// macOS writes by itself, where `synchronize()` is harmless.
struct KarmaDefaultsMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        if request.method != .GET {
            UserDefaults.standard.synchronize()
        }
        return response
    }
}
