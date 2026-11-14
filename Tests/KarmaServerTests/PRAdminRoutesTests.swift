// by cipher.org.uk
#if WebServer
import Foundation
import NIOCore
import XCTVapor
@testable import KarmaServer

/// The accounts and repositories routes. Only calls that cannot write are made: refusals that happen before the
/// store is touched, reads, and unknown ids. `HOME` and the XDG folders point at a throwaway folder, so the reads
/// never see the real user's accounts or caches.
final class PRAdminRoutesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("karma-pr-admin-\(UUID().uuidString)")
        for variable in ["HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"] {
            setenv(variable, home.path, 1)
        }
    }

    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        registerPRAdminRoutes(app.grouped("api").grouped(KarmaErrorMiddleware()))
        return app
    }

    private func headers(json: Bool = false) -> HTTPHeaders {
        var headers: HTTPHeaders = ["X-Karma-Client": "web", "Host": "127.0.0.1"]
        if json { headers.add(name: .contentType, value: "application/json") }
        return headers
    }

    private func body(_ json: String) -> ByteBuffer {
        ByteBuffer(string: json)
    }

    private func object(_ res: XCTHTTPResponse) throws -> [String: Any]? {
        try JSONSerialization.jsonObject(with: Data(res.body.readableBytesView)) as? [String: Any]
    }

    func testSaveAccountRefusesEmptyUsernameWithTheDialogText() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/pr/accounts",
                           headers: headers(json: true),
                           body: body(#"{"provider":"github","host":"","username":"   ","token":"abc"}"#)) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertEqual(try self.object(res)?["error"] as? String, "Enter a username to identify this account.")
        }
    }

    func testSaveAccountRefusesEmptyTokenWithTheDialogText() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/pr/accounts",
                           headers: headers(json: true),
                           body: body(#"{"provider":"github","host":"","username":"alice","token":"  "}"#)) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertEqual(try self.object(res)?["error"] as? String, "Paste a token to save.")
        }
    }

    func testAccountsListsProvidersWithHints() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/pr/accounts", headers: headers()) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let providers = try self.object(res)?["providers"] as? [[String: Any]]
            XCTAssertEqual(providers?.compactMap { $0["id"] as? String }, ["github", "gitlab", "gitea", "bitbucket"])
            XCTAssertNotNil(try self.object(res)?["accounts"] as? [Any])
        }
    }

    func testResolveProviderMovesToKnownPublicHost() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/pr/accounts/provider?provider=github&host=gitlab.com", headers: headers()) { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(try self.object(res)?["provider"] as? String, "gitlab")
        }
    }

    func testTestingAnUnknownAccountIsNotFound() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/pr/accounts/test",
                           headers: headers(json: true),
                           body: body(#"{"identity":"github|https://api.github.com|nobody"}"#)) { res async throws in
            XCTAssertEqual(res.status, .notFound)
            XCTAssertEqual(try self.object(res)?["error"] as? String, "That account is no longer saved.")
        }
    }

    func testRemovingAnUnknownAccountIsNotFound() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.DELETE, "api/pr/accounts?identity=github%7Chttps%3A%2F%2Fapi.github.com%7Cnobody",
                           headers: headers()) { res async throws in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    func testRepositoriesListsDepthChoicesAndCache() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/pr/repos", headers: headers()) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let object = try self.object(res)
            XCTAssertNotNil(object?["repos"] as? [Any])
            XCTAssertEqual((object?["depthChoices"] as? [Any])?.isEmpty, false)
            XCTAssertNotNil(object?["cache"] as? [String: Any])
        }
    }

    func testDetectingANonURLReportsItInTheStatusLine() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/pr/repos/detect", headers: headers(json: true),
                           body: body(#"{"url":"not a url"}"#)) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let object = try self.object(res)
            XCTAssertEqual(object?["recognised"] as? Bool, false)
            XCTAssertEqual(object?["statusText"] as? String, "Could not read that as a repository URL.")
            XCTAssertEqual(object?["statusTone"] as? String, "error")
        }
    }

    func testAddingARepositoryWithoutAURLIsRefused() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/pr/repos", headers: headers(json: true),
                           body: body(#"{"url":"","baseBranches":""}"#)) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertEqual(try self.object(res)?["error"] as? String,
                           "Enter a full repository URL, for example https://github.com/owner/name.")
        }
    }

    func testTestingARepositoryWithoutAURLIsRefusedAtOnce() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/pr/repos/test", headers: headers(json: true),
                           body: body(#"{"url":"nonsense"}"#)) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    /// The id `github|https://api.github.com|owner/name` sent as one percent-encoded path segment. The 404 carries
    /// the service's text, which proves the route matched, the id decoded and the body decoded.
    func testUpdatingARepositoryRoutesEncodedIdAsOneSegment() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        let id = "github%7Chttps%3A%2F%2Fapi.github.com%7Cowner%2Fname"
        try await app.test(.PUT, "api/pr/repos/\(id)", headers: headers(json: true),
                           body: body(#"{"enabled":false}"#)) { res async throws in
            XCTAssertEqual(res.status, .notFound)
            XCTAssertEqual(try self.object(res)?["error"] as? String, "That repository is no longer watched.")
        }
    }

    func testRemovePromptAndRemoveOfUnknownRepositoryAreNotFound() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/pr/repos/remove-prompt?id=github%7Chttps%3A%2F%2Fapi.github.com%7Cnobody",
                           headers: headers()) { res async throws in
            XCTAssertEqual(res.status, .notFound)
        }
        try await app.test(.DELETE, "api/pr/repos?id=github%7Chttps%3A%2F%2Fapi.github.com%7Cnobody",
                           headers: headers()) { res async throws in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    func testCachePromptIsWrappedAndNullWhenEmpty() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/pr/cache/prompt", headers: headers()) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let object = try self.object(res)
            XCTAssertTrue(object?.keys.contains("prompt") == true)
            XCTAssertTrue(object?["prompt"] is NSNull || object?["prompt"] is [String: Any])
        }
    }
}
#endif
