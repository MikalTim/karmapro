// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The body of `GET /api/ai`: the settings (with the provider and prompt lists in `settings.providers`
/// and `settings.prompts`) and the chat (transcript, streaming state and buttons) in one reply.
private struct AIOverviewDTO: Encodable {
    let settings: AISettingsService.AISettingsDTO
    let chat: AIChatService.StateDTO
}

private struct AISettingsBody: Decodable {
    var providerID: String?
    var model: String?
    var apiKey: String?
    var serverURL: String?
}

private struct AIProviderBody: Decodable {
    var name: String
    var baseURL: String
    var requiresAPIKey: Bool
    /// Optional, defaults to an empty key.
    var apiKey: String?
}

private struct AIPromptBody: Decodable {
    var title: String
    /// Optional, defaults to an empty prompt.
    var promptText: String?
}

private struct AIChatTextBody: Decodable {
    var text: String
}

private struct AIHowToFixBody: Decodable {
    var path: String
    var line: Int
    var lineText: String
}

private struct AIQuestionBody: Decodable {
    var question: String
}

private struct AIConnectBody: Decodable {
    var apiKey: String
    var serverURL: String?
}

/// The `:id` path parameter; a missing one is a 400.
private func pathID(_ req: Request) throws -> String {
    guard let id = req.parameters.get("id") else { throw Abort(.badRequest, reason: "The path needs an id.") }
    return id
}

/// Registers the AI assistant routes: settings, endpoints (providers), prompt templates and the chat.
/// `AISettingsService` and `AIChatService` hold the logic; the chat answers through `ai.stream` events.
func registerAIRoutes(_ api: RoutesBuilder) {
    // GET /api/ai
    //   request: none
    //   response: AIOverviewDTO = {"settings": AISettingsService.AISettingsDTO, "chat": AIChatService.StateDTO}
    api.get("ai") { req async throws -> Response in
        let overview = try await req.service {
            AIOverviewDTO(settings: AISettingsService.state(), chat: AIChatService.shared.state())
        }
        return jsonResponse(overview)
    }

    // PUT /api/ai/settings {providerID?, model?, apiKey?, serverURL?}
    //   Only the fields sent are changed. A change of provider or server starts a model refresh.
    //   response: AISettingsService.AIUpdateDTO (settings, status?, level?, refreshJobID?)
    api.put("ai", "settings") { req async throws -> Response in
        let body = try req.jsonBody(AISettingsBody.self)
        let result = try await req.service {
            try AISettingsService.update(providerID: body.providerID, model: body.model,
                                         apiKey: body.apiKey, serverURL: body.serverURL)
        }
        return jsonResponse(result)
    }

    // POST /api/ai/models/refresh
    //   request: none
    //   response: {"jobId"}; the job result is AISettingsService.AIModelsResultDTO
    api.post("ai", "models", "refresh") { req async throws -> Response in
        let jobID = try await req.service { AISettingsService.refreshModels() }
        return jobStartedResponse(jobID)
    }

    // POST /api/ai/connect {apiKey, serverURL?}
    //   The Connect button: checks the endpoint and saves the key.
    //   response: {"jobId"}; the job result is AISettingsService.AIStatusDTO
    api.post("ai", "connect") { req async throws -> Response in
        let body = try req.jsonBody(AIConnectBody.self)
        let jobID = try await req.service {
            AISettingsService.connect(apiKey: body.apiKey, serverURL: body.serverURL)
        }
        return jobStartedResponse(jobID)
    }

    // POST /api/ai/providers {name, baseURL, requiresAPIKey, apiKey?}
    //   response: AISettingsService.AISettingsDTO. 400 when a field is invalid, nothing is saved.
    api.post("ai", "providers") { req async throws -> Response in
        let body = try req.jsonBody(AIProviderBody.self)
        let settings = try await req.service {
            try AISettingsService.addProvider(name: body.name, baseURL: body.baseURL,
                                              requiresAPIKey: body.requiresAPIKey, apiKey: body.apiKey ?? "")
        }
        return jsonResponse(settings)
    }

    // PUT /api/ai/providers/:id {name, baseURL, requiresAPIKey, apiKey?}
    //   Edits a user endpoint. 404 for an unknown id, 400 for a built-in one or an invalid field.
    //   response: AISettingsService.AISettingsDTO
    api.put("ai", "providers", ":id") { req async throws -> Response in
        let id = try pathID(req)
        let body = try req.jsonBody(AIProviderBody.self)
        let settings = try await req.service {
            try AISettingsService.updateProvider(id: id, name: body.name, baseURL: body.baseURL,
                                                 requiresAPIKey: body.requiresAPIKey, apiKey: body.apiKey ?? "")
        }
        return jsonResponse(settings)
    }

    // GET /api/ai/providers/:id/key
    //   The saved key of a user endpoint, which the edit sheet prefills as AppKit's does. Kept out of the settings
    //   reply so a state fetch never carries every endpoint's key. 404 unknown id, 400 for a built-in one.
    //   response: {"apiKey"}
    api.get("ai", "providers", ":id", "key") { req async throws -> Response in
        struct Body: Encodable { let apiKey: String }
        let id = try pathID(req)
        let key = try await req.service { try AISettingsService.providerKey(id: id) }
        return jsonResponse(Body(apiKey: key))
    }

    // DELETE /api/ai/providers/:id
    //   Removes a user endpoint with its key and model. 404 unknown id, 400 for a built-in one.
    //   response: AISettingsService.AISettingsDTO
    api.delete("ai", "providers", ":id") { req async throws -> Response in
        let id = try pathID(req)
        let settings = try await req.service { try AISettingsService.deleteProvider(id: id) }
        return jsonResponse(settings)
    }

    // POST /api/ai/providers/:id/test
    //   request: none
    //   response: {"jobId"}; the job result is AISettingsService.AIStatusDTO
    api.post("ai", "providers", ":id", "test") { req async throws -> Response in
        let id = try pathID(req)
        let jobID = try await req.service { try AISettingsService.testProvider(id: id) }
        return jobStartedResponse(jobID)
    }

    // POST /api/ai/prompts {title, promptText?}
    //   response: AISettingsService.AISettingsDTO. 400 when the title is blank.
    api.post("ai", "prompts") { req async throws -> Response in
        let body = try req.jsonBody(AIPromptBody.self)
        let settings = try await req.service {
            try AISettingsService.addPrompt(title: body.title, promptText: body.promptText ?? "")
        }
        return jsonResponse(settings)
    }

    // PUT /api/ai/prompts/:id {title, promptText?}
    //   response: AISettingsService.AISettingsDTO. 404 unknown id, 400 blank title.
    api.put("ai", "prompts", ":id") { req async throws -> Response in
        let id = try pathID(req)
        let body = try req.jsonBody(AIPromptBody.self)
        let settings = try await req.service {
            try AISettingsService.updatePrompt(id: id, title: body.title, promptText: body.promptText ?? "")
        }
        return jsonResponse(settings)
    }

    // DELETE /api/ai/prompts/:id
    //   The confirmation is the front end's. 404 for an unknown id.
    //   response: AISettingsService.AISettingsDTO
    api.delete("ai", "prompts", ":id") { req async throws -> Response in
        let id = try pathID(req)
        let settings = try await req.service { try AISettingsService.deletePrompt(id: id) }
        return jsonResponse(settings)
    }

    // GET /api/ai/prompts/export
    //   response: the file KarmaPro-Prompts.json (application/json), a JSON array of prompt templates.
    api.get("ai", "prompts", "export") { req async throws -> Response in
        let export = try await req.service { AISettingsService.exportPrompts() }
        return downloadResponse(fileName: export.fileName, data: export.data, contentType: "application/json")
    }

    // POST /api/ai/prompts/import (raw file body, ?filename=)
    //   request: a prompts export file (application/octet-stream). 400 when the file is not one.
    //   response: AISettingsService.AIPromptImportDTO {added, skipped, status, level}
    api.post("ai", "prompts", "import") { req async throws -> Response in
        let data = try req.uploadedData()
        let result = try await req.service { try AISettingsService.importPrompts(data: data) }
        return jsonResponse(result)
    }

    // POST /api/ai/chat/send {text}
    //   A blank text is not an error: the reply carries the hint in `chat.status`.
    //   response: AIChatService.StateDTO
    api.post("ai", "chat", "send") { req async throws -> Response in
        let body = try req.jsonBody(AIChatTextBody.self)
        let state = try await req.service { AIChatService.shared.send(text: body.text) }
        return jsonResponse(state)
    }

    // POST /api/ai/chat/continue
    //   Resumes an interrupted task. Does nothing when there is nothing to resume.
    //   response: AIChatService.StateDTO
    api.post("ai", "chat", "continue") { req async throws -> Response in
        let state = try await req.service { AIChatService.shared.continueTurn() }
        return jsonResponse(state)
    }

    // POST /api/ai/chat/new
    //   Clears the conversation. Refused while a request runs (the state says so).
    //   response: AIChatService.StateDTO
    api.post("ai", "chat", "new") { req async throws -> Response in
        let state = try await req.service { AIChatService.shared.newChat() }
        return jsonResponse(state)
    }

    // POST /api/ai/chat/stop
    //   request: none
    //   response: AIChatService.StateDTO
    api.post("ai", "chat", "stop") { req async throws -> Response in
        let state = try await req.service { AIChatService.shared.stop() }
        return jsonResponse(state)
    }

    // POST /api/ai/chat/how-to-fix {path, line, lineText}
    //   Sends the "How to fix" request for a finding, as the Send button does.
    //   response: AIChatService.StateDTO
    api.post("ai", "chat", "how-to-fix") { req async throws -> Response in
        let body = try req.jsonBody(AIHowToFixBody.self)
        let state = try await req.service {
            AIChatService.shared.askHowToFix(path: body.path, line: body.line, lineText: body.lineText)
        }
        return jsonResponse(state)
    }

    // POST /api/ai/chat/ask {question}
    //   Sends a ready-made question, as the Send button does.
    //   response: AIChatService.StateDTO
    api.post("ai", "chat", "ask") { req async throws -> Response in
        let body = try req.jsonBody(AIQuestionBody.self)
        let state = try await req.service { AIChatService.shared.ask(body.question) }
        return jsonResponse(state)
    }
}
