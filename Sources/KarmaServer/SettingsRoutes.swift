// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

private struct MCPSettingsBody: Decodable {
    var allowAI: Bool?
    var autoStart: Bool?
}

private struct UpdateAutomaticBody: Decodable {
    var enabled: Bool
}

/// Registers the Settings routes for the MCP service (`KarmaMCP`) and the update checks (`UpdateService`).
/// Every MCP route answers with the MCP state, so a front end can show the result of the change at once.
func registerSettingsRoutes(_ api: RoutesBuilder) {
    // GET /api/mcp
    //   request: none
    //   response: KarmaMCP's MCPStateDTO {running, url, clientConfig, port, allowAI, autoStart, scanCount, lastError, startedAt?}
    api.get("mcp") { req async throws -> Response in
        let state = try await req.service { KarmaMCP.state() }
        return jsonResponse(state)
    }

    // POST /api/mcp/toggle
    //   Starts the listener when it is stopped, stops it when it runs. A start that fails (for example no
    //   free port in 8765–8775) is not an HTTP error: the reply is the state, with the reason in `lastError`.
    //   response: MCPStateDTO
    api.post("mcp", "toggle") { req async throws -> Response in
        let state = try await req.service { () throws -> MCPStateDTO in
            do {
                try KarmaMCP.toggle()
            } catch {
                // The service records a failed start in `lastError`. An error it did not record is a real failure.
                guard !KarmaMCP.state().lastError.isEmpty else { throw error }
            }
            return KarmaMCP.state()
        }
        return jsonResponse(state)
    }

    // PUT /api/mcp {allowAI?, autoStart?}
    //   Changes only the fields sent. 400 when the body is empty or malformed.
    //   response: MCPStateDTO
    api.put("mcp") { req async throws -> Response in
        let body = try req.jsonBody(MCPSettingsBody.self)
        let state = try await req.service { () -> MCPStateDTO in
            if let allowAI = body.allowAI {
                KarmaMCP.setAllowAI(allowAI)
            }
            if let autoStart = body.autoStart {
                KarmaMCP.setAutoStart(autoStart)
            }
            return KarmaMCP.state()
        }
        return jsonResponse(state)
    }

    // POST /api/mcp/rotate-token
    //   Replaces the access token in the client address. A running listener restarts with the new one.
    //   response: MCPStateDTO
    api.post("mcp", "rotate-token") { req async throws -> Response in
        let state = try await req.service { () -> MCPStateDTO in
            KarmaMCP.rotateToken()
            return KarmaMCP.state()
        }
        return jsonResponse(state)
    }

    // GET /api/updates
    //   request: none
    //   response: UpdateService.UpdateStateDTO {currentVersion, automaticChecks, lastCheckedAt?, checkRunning,
    //   checkMenuTitle, knownNewerVersion?, availableMenuTitle?, downloadURL, lastOutcome?}
    api.get("updates") { req async throws -> Response in
        let state = try await req.service { UpdateService.state() }
        return jsonResponse(state)
    }

    // POST /api/updates/check
    //   Starts a manual check against GitHub. A check already running is returned as is.
    //   response: {"jobId"}; the job result is UpdateService.UpdateOutcomeDTO
    api.post("updates", "check") { req async throws -> Response in
        let jobID = try await req.service { try UpdateService.check(manual: true) }
        return jobStartedResponse(jobID)
    }

    // PUT /api/updates/automatic {enabled}
    //   Turns the daily check on or off. Turning it on starts a check at once when the daily gate allows;
    //   that check's progress and outcome arrive as `update.changed` events.
    //   response: UpdateService.UpdateStateDTO
    api.put("updates", "automatic") { req async throws -> Response in
        let body = try req.jsonBody(UpdateAutomaticBody.self)
        let state = try await req.service { () -> UpdateService.UpdateStateDTO in
            UpdateService.setAutomatic(body.enabled)
            return UpdateService.state()
        }
        return jsonResponse(state)
    }
}
