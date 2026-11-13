// by cipher.org.uk
#if WebServer
import XCTVapor
@testable import KarmaServer

final class AuthTests: XCTestCase {
    private func makeApp(token: String?) async throws -> Application {
        let app = try await Application.make(.testing)
        try configure(app, token: token)
        return app
    }

    func testRequestWithoutClientHeaderIsForbidden() async throws {
        let app = try await makeApp(token: nil)
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/app/info", headers: ["Host": "127.0.0.1:8790"]) { res async in
            XCTAssertEqual(res.status, .forbidden)
        }
    }

    func testLoopbackModeRejectsForeignHostHeader() async throws {
        let app = try await makeApp(token: nil)
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/app/info", headers: ["X-Karma-Client": "web", "Host": "evil.example"]) { res async in
            XCTAssertEqual(res.status, .misdirectedRequest)
        }
    }

    func testLoopbackModeAcceptsLocalhostAndIPv6Hosts() async throws {
        let app = try await makeApp(token: nil)
        defer { Task { try? await app.asyncShutdown() } }
        for host in ["localhost:8790", "127.0.0.1", "[::1]:8790"] {
            try await app.test(.GET, "api/app/info", headers: ["X-Karma-Client": "web", "Host": host]) { res async in
                XCTAssertEqual(res.status, .ok, host)
            }
        }
    }

    func testTokenModeRequiresBearerToken() async throws {
        let app = try await makeApp(token: "secret")
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/app/info", headers: ["X-Karma-Client": "web"]) { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try await app.test(.GET, "api/app/info", headers: ["X-Karma-Client": "web", "Authorization": "Bearer wrong"]) { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try await app.test(.GET, "api/app/info", headers: ["X-Karma-Client": "web", "Authorization": "Bearer secret"]) { res async in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testTokenInQueryStringIsOnlyAcceptedForTheEventStream() async throws {
        let app = try await makeApp(token: "secret")
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/app/info?token=secret", headers: ["X-Karma-Client": "web"]) { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    func testInfoReportsVersionPlatformAndTokenMode() async throws {
        let app = try await makeApp(token: "secret")
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/app/info", headers: ["X-Karma-Client": "web", "Authorization": "Bearer secret"]) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let object = try JSONSerialization.jsonObject(with: Data(res.body.readableBytesView)) as? [String: Any]
            XCTAssertEqual(object?["tokenRequired"] as? Bool, true)
            XCTAssertNotNil(object?["version"] as? String)
            XCTAssertNotNil(object?["openBugCount"] as? Int)
        }
    }

    func testErrorsAreJSONWithErrorField() async throws {
        let app = try await makeApp(token: nil)
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/app/info", headers: ["Host": "127.0.0.1"]) { res async throws in
            XCTAssertEqual(res.headers.contentType?.serialize().hasPrefix("application/json"), true)
            let object = try JSONSerialization.jsonObject(with: Data(res.body.readableBytesView)) as? [String: String]
            XCTAssertEqual(object?["error"], "missing client header")
        }
    }
}
#endif
