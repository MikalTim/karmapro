// by cipher.org.uk
#if WebServer
import Foundation
import KarmaCore
import Vapor
import XCTVapor
@testable import KarmaServer

/// The AI, ML and Settings routes (MCP and updates) through the real services. HOME and the XDG folders point
/// at a temporary directory while the class runs, so the stores these routes touch cannot reach the real
/// library or settings. No test sends an AI request, starts the MCP listener, downloads anything, or stores a
/// key, provider, prompt, model or update preference: only refused requests and read-only queries are sent.
final class AIMLRoutesTests: XCTestCase {
    private static var sandbox: URL?
    private static var savedHome: String?
    private static var savedDataHome: String?
    private static var savedConfigHome: String?

    override class func setUp() {
        super.setUp()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("karma-ai-ml-routes-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        sandbox = root
        savedHome = ProcessInfo.processInfo.environment["HOME"]
        savedDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        savedConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        setenv("HOME", root.path, 1)
        setenv("XDG_DATA_HOME", root.path, 1)
        setenv("XDG_CONFIG_HOME", root.path, 1)
    }

    override class func tearDown() {
        restore("HOME", savedHome)
        restore("XDG_DATA_HOME", savedDataHome)
        restore("XDG_CONFIG_HOME", savedConfigHome)
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
        super.tearDown()
    }

    private class func restore(_ name: String, _ value: String?) {
        if let value { setenv(name, value, 1) } else { unsetenv(name) }
    }

    private let headers: HTTPHeaders = ["X-Karma-Client": "web", "Host": "127.0.0.1"]
    private var jsonHeaders: HTTPHeaders {
        var all = headers
        all.add(name: .contentType, value: "application/json")
        return all
    }

    /// The application with only the three route groups under test, on the same `/api` group the server uses.
    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        let api = app.grouped("api").grouped(KarmaErrorMiddleware())
        registerAIRoutes(api)
        registerMLRoutes(api)
        registerSettingsRoutes(api)
        return app
    }

    private func object(_ res: XCTHTTPResponse) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(res.body.readableBytesView)) as? [String: Any])
    }

    private func errorText(_ res: XCTHTTPResponse) throws -> String? {
        try object(res)["error"] as? String
    }

    // MARK: - AI assistant

    func testOverviewCombinesSettingsAndChat() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/ai", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let body = try self.object(res)
            let settings = try XCTUnwrap(body["settings"] as? [String: Any])
            XCTAssertFalse((settings["providers"] as? [Any] ?? []).isEmpty)
            XCTAssertNotNil(settings["selectedProviderID"] as? String)
            let chat = try XCTUnwrap(body["chat"] as? [String: Any])
            XCTAssertEqual(chat["requestInFlight"] as? Bool, false)
            XCTAssertEqual(chat["sendTitle"] as? String, "Send to AI")
        }
    }

    func testBlankChatTextReturnsTheHintAsStatus() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/ai/chat/send", headers: jsonHeaders, body: ByteBuffer(string: #"{"text":"   "}"#)) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let chat = try self.object(res)
            XCTAssertEqual(chat["status"] as? String, "Type or paste a prompt first.")
            XCTAssertEqual(chat["statusLevel"] as? String, "error")
        }
    }

    func testChatSendWithoutTextIsBadRequest() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/ai/chat/send", headers: jsonHeaders, body: ByteBuffer(string: "{}")) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertNotNil(try self.errorText(res))
        }
    }

    func testIdleChatControlsLeaveAnEmptyConversation() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/ai/chat/new", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let chat = try XCTUnwrap(try self.object(res)["transcript"] as? [Any])
            XCTAssertTrue(chat.isEmpty)
        }
        try await app.test(.POST, "api/ai/chat/continue", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(try self.object(res)["canContinue"] as? Bool, false)
        }
        try await app.test(.POST, "api/ai/chat/stop", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(try self.object(res)["requestInFlight"] as? Bool, false)
        }
    }

    func testAddProviderRejectsBlankNameAndSavesNothing() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        let body = #"{"name":" ","baseURL":"https://example.invalid/v1","requiresAPIKey":false}"#
        try await app.test(.POST, "api/ai/providers", headers: jsonHeaders, body: ByteBuffer(string: body)) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertEqual(try self.errorText(res), "Enter a name for this provider.")
        }
    }

    func testUnknownProviderIsNotFound() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        let body = #"{"name":"Other","baseURL":"https://example.invalid/v1","requiresAPIKey":false}"#
        try await app.test(.PUT, "api/ai/providers/no-such-provider", headers: jsonHeaders, body: ByteBuffer(string: body)) { res async throws in
            XCTAssertEqual(res.status, .notFound)
        }
        try await app.test(.DELETE, "api/ai/providers/no-such-provider", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .notFound)
        }
        try await app.test(.POST, "api/ai/providers/no-such-provider/test", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    func testProviderKeyIsReadPerProviderAndNeverInTheSettings() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/ai/providers/no-such-provider/key", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .notFound)
        }
        // A built-in preset's key is edited in the assistant window, so the edit sheet's route refuses it.
        try await app.test(.GET, "api/ai/providers/builtin.openrouter/key", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        }
        // The settings reply lists every endpoint on each state fetch; no endpoint entry may carry a key.
        try await app.test(.GET, "api/ai", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let settings = try XCTUnwrap(try self.object(res)["settings"] as? [String: Any])
            let providers = try XCTUnwrap(settings["providers"] as? [[String: Any]])
            XCTAssertFalse(providers.isEmpty)
            XCTAssertTrue(providers.allSatisfy { $0["apiKey"] == nil })
        }
    }

    func testSettingsWithUnknownProviderIsNotFound() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.PUT, "api/ai/settings", headers: jsonHeaders, body: ByteBuffer(string: #"{"providerID":"no-such-provider"}"#)) { res async throws in
            XCTAssertEqual(res.status, .notFound)
        }
        try await app.test(.PUT, "api/ai/settings", headers: jsonHeaders) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testBlankPromptTitleIsBadRequest() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/ai/prompts", headers: jsonHeaders, body: ByteBuffer(string: #"{"title":"  ","promptText":"x"}"#)) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertEqual(try self.errorText(res), "Enter a title for the prompt.")
        }
    }

    func testUnknownPromptIsNotFound() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.PUT, "api/ai/prompts/no-such-prompt", headers: jsonHeaders, body: ByteBuffer(string: #"{"title":"T"}"#)) { res async throws in
            XCTAssertEqual(res.status, .notFound)
        }
        try await app.test(.DELETE, "api/ai/prompts/no-such-prompt", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    func testPromptExportIsAJSONDownload() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/ai/prompts/export", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertTrue(res.headers.first(name: .contentDisposition)?.contains("KarmaPro-Prompts.json") == true)
            let prompts = try JSONSerialization.jsonObject(with: Data(res.body.readableBytesView))
            XCTAssertNotNil(prompts as? [Any])
        }
    }

    func testGarbagePromptFileIsBadRequest() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/ai/prompts/import?filename=prompts.json", headers: headers, body: ByteBuffer(string: "not json")) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertEqual(try self.errorText(res), "Import failed: the file is not a valid Karma Pro prompts export.")
        }
    }

    // MARK: - ML

    func testModelsListsModelsAndTrainingLanguages() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/ml/models", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let body = try self.object(res)
            XCTAssertNotNil(body["models"] as? [Any])
            let options = try XCTUnwrap(body["options"] as? [String: Any])
            let languages = try XCTUnwrap(options["trainingLanguages"] as? [[String: Any]])
            XCTAssertFalse(languages.isEmpty)
            XCTAssertFalse(languages.contains { $0["name"] as? String == "All Languages" })
        }
    }

    func testTrainWithoutFolderIsBadRequest() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/ml/train", headers: jsonHeaders, body: ByteBuffer(string: #"{"folder":"","language":"C","name":"m"}"#)) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertNotNil(try self.errorText(res))
        }
    }

    func testTrainWithMissingFolderIsBadRequest() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        var language = ""
        try await app.test(.GET, "api/ml/models", headers: headers) { res async throws in
            let options = try XCTUnwrap(try self.object(res)["options"] as? [String: Any])
            let languages = try XCTUnwrap(options["trainingLanguages"] as? [[String: Any]])
            language = try XCTUnwrap(languages.first?["name"] as? String)
        }
        let missing = try XCTUnwrap(Self.sandbox).appendingPathComponent("no-such-folder").path
        let body = #"{"folder":"\#(missing)","language":"\#(language)","name":"m"}"#
        try await app.test(.POST, "api/ml/train", headers: jsonHeaders, body: ByteBuffer(string: body)) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertNotNil(try self.errorText(res))
        }
    }

    func testImportOfGarbageModelIsBadRequest() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/ml/models/import?filename=garbage.karmamodel", headers: headers, body: ByteBuffer(string: "garbage")) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertEqual(try self.errorText(res), "Not a valid Karma Pro model file.")
        }
    }

    func testImportRejectsOtherFileTypesAndMissingBodies() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/ml/models/import?filename=notes.txt", headers: headers, body: ByteBuffer(string: "x")) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        }
        try await app.test(.POST, "api/ml/models/import?filename=model.karmamodel", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testImportURLNeedsAnAddress() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/ml/models/import-url", headers: jsonHeaders, body: ByteBuffer(string: #"{"url":""}"#)) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertEqual(try self.errorText(res), "Enter a valid web address.")
        }
    }

    func testExportOfUnknownModelIsRefused() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/ml/models/no-such-model/export", headers: headers) { res async throws in
            // 400 when the library is empty, 404 when other models exist; a download never succeeds here.
            XCTAssertTrue([HTTPStatus.badRequest, .notFound].contains(res.status), "\(res.status)")
        }
    }

    func testScanWithoutModelIsBadRequest() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.POST, "api/ml/scan", headers: jsonHeaders, body: ByteBuffer(string: #"{"model":"","threshold":70}"#)) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertNotNil(try self.errorText(res))
        }
    }

    func testHeatmapIsJSON() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/ml/heatmap", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let body = try self.object(res)
            XCTAssertNotNil(body["cells"] as? [Any])
            XCTAssertNotNil(body["summary"] as? String)
        }
    }

    // MARK: - Settings: MCP and updates

    func testMCPStateIsJSON() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/mcp", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let body = try self.object(res)
            XCTAssertNotNil(body["running"] as? Bool)
            XCTAssertNotNil(body["port"] as? Int)
            XCTAssertTrue((body["url"] as? String)?.contains("/mcp/") == true)
            XCTAssertNotNil(body["lastError"] as? String)
        }
    }

    func testMCPChangeWithoutBodyIsBadRequest() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.PUT, "api/mcp", headers: jsonHeaders) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testUpdateStateIsJSON() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.GET, "api/updates", headers: headers) { res async throws in
            XCTAssertEqual(res.status, .ok)
            let body = try self.object(res)
            XCTAssertFalse((body["currentVersion"] as? String ?? "").isEmpty)
            XCTAssertNotNil(body["automaticChecks"] as? Bool)
            XCTAssertNotNil(body["checkMenuTitle"] as? String)
        }
    }

    func testAutomaticUpdateSettingNeedsTheFlag() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.asyncShutdown() } }
        try await app.test(.PUT, "api/updates/automatic", headers: jsonHeaders, body: ByteBuffer(string: "{}")) { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        }
    }
}
#endif
