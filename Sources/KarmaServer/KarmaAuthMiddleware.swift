// by cipher.org.uk
import Foundation
import Vapor
#if canImport(Glibc)
import Glibc
#endif

/// Protects the `/api` routes.
///
/// Loopback mode (the server listens on 127.0.0.1, ::1 or localhost): a request
/// whose `Host` header names any other host is rejected with 421. A web page on
/// another site cannot reach the server through DNS rebinding, because the
/// browser sends the attacker's host name in `Host`.
///
/// Token mode (any other listening address): every request needs the access
/// token printed at startup, as `Authorization: Bearer <token>`. The event
/// stream may carry it as `?token=` instead, because `EventSource` cannot set
/// request headers.
///
/// Both modes: every request except the event stream must carry
/// `X-Karma-Client: web`. A custom header forces a CORS preflight for requests
/// from other sites, and the server sends no CORS headers, so cross-site form
/// and fetch posts are refused by the browser.
struct KarmaAuthMiddleware: AsyncMiddleware {
    /// The access token, or nil in loopback mode.
    let token: String?

    static let loopbackHosts: Set<String> = ["127.0.0.1", "::1", "localhost"]

    static func isLoopback(_ host: String) -> Bool {
        loopbackHosts.contains(host.lowercased())
    }

    /// 32 random bytes as lowercase hex.
    static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32)
            .map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }

    /// The host name inside a `Host` header value: `localhost:8790` → `localhost`,
    /// `[::1]:8790` → `::1`.
    static func hostname(fromHostHeader value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") {
            return String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        }
        if let colon = trimmed.firstIndex(of: ":") {
            return String(trimmed[..<colon])
        }
        return trimmed
    }

    /// Compares two strings in time that does not depend on where they differ.
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var difference = x.count ^ y.count
        for i in 0..<max(x.count, y.count) {
            let left: UInt8 = i < x.count ? x[i] : 0
            let right: UInt8 = i < y.count ? y[i] : 0
            difference |= Int(left ^ right)
        }
        return difference == 0
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let isEventStream = request.method == .GET && request.url.path == "/api/events"

        if token == nil {
            let host = request.headers.first(name: "Host") ?? ""
            if !Self.loopbackHosts.contains(Self.hostname(fromHostHeader: host)) {
                return jsonErrorResponse("This server only answers requests addressed to localhost.", status: .misdirectedRequest)
            }
        }

        if let token {
            var supplied: String?
            if let bearer = request.headers.bearerAuthorization?.token {
                supplied = bearer
            } else if isEventStream {
                supplied = request.query[String.self, at: "token"]
            }
            guard let supplied, Self.constantTimeEquals(supplied, token) else {
                return jsonErrorResponse("unauthorized", status: .unauthorized)
            }
        }

        if !isEventStream && request.headers.first(name: "X-Karma-Client") != "web" {
            return jsonErrorResponse("missing client header", status: .forbidden)
        }

        return try await next.respond(to: request)
    }
}
