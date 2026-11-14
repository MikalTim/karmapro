// by cipher.org.uk
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The AI assistant's provider, model, API key, Ollama server and prompt-template
/// settings, plus the endpoint manager (`ProviderManagerController` and its editor).
/// The chat itself lives in `AIChatService`.
///
/// Status texts and their colour levels are the ones the AppKit window shows.
/// Levels are `info` (secondary label), `error` (red), `warning` (orange) and `success` (green).
public enum AISettingsService {

    // MARK: - DTOs

    /// A provider as the dropdown and the endpoint table show it.
    public struct AIProviderDTO: Codable, Sendable {
        public var id: String
        public var name: String
        /// The base URL; for Ollama, the server URL currently in use.
        public var baseURL: String
        public var requiresAPIKey: Bool
        public var isBuiltin: Bool
        public var isOllama: Bool
        /// The dropdown title: the name, with "  (custom)" for user endpoints.
        public var popupTitle: String
        /// The endpoint table's name column: the name, with "  (built-in)" for presets.
        public var tableName: String
        /// The endpoint table's key column: "required" or "none".
        public var tableKey: String

        public init(id: String, name: String, baseURL: String, requiresAPIKey: Bool, isBuiltin: Bool,
                    isOllama: Bool, popupTitle: String, tableName: String, tableKey: String) {
            self.id = id
            self.name = name
            self.baseURL = baseURL
            self.requiresAPIKey = requiresAPIKey
            self.isBuiltin = isBuiltin
            self.isOllama = isOllama
            self.popupTitle = popupTitle
            self.tableName = tableName
            self.tableKey = tableKey
        }
    }

    /// A saved prompt template, in the order the prompt dropdown lists them.
    public struct AIPromptDTO: Codable, Sendable {
        public var id: String
        public var title: String
        public var promptText: String
        public var isBuiltin: Bool

        public init(id: String, title: String, promptText: String, isBuiltin: Bool) {
            self.id = id
            self.title = title
            self.promptText = promptText
            self.isBuiltin = isBuiltin
        }
    }

    /// Everything the AI settings show.
    public struct AISettingsDTO: Codable, Sendable {
        public var providers: [AIProviderDTO]
        public var selectedProviderID: String
        public var requiresAPIKey: Bool
        public var isOllama: Bool
        /// The API key field's value.
        public var apiKey: String
        /// The Ollama server field's value (the stored, normalised URL).
        public var serverURL: String
        /// The server field's placeholder.
        public var serverPlaceholder: String
        public var models: [String]
        public var selectedModel: String
        public var prompts: [AIPromptDTO]
        /// The text of the last status line this service produced.
        public var status: String
        /// "info", "error", "warning" or "success".
        public var level: String

        public init(providers: [AIProviderDTO], selectedProviderID: String, requiresAPIKey: Bool, isOllama: Bool,
                    apiKey: String, serverURL: String, serverPlaceholder: String, models: [String],
                    selectedModel: String, prompts: [AIPromptDTO], status: String, level: String) {
            self.providers = providers
            self.selectedProviderID = selectedProviderID
            self.requiresAPIKey = requiresAPIKey
            self.isOllama = isOllama
            self.apiKey = apiKey
            self.serverURL = serverURL
            self.serverPlaceholder = serverPlaceholder
            self.models = models
            self.selectedModel = selectedModel
            self.prompts = prompts
            self.status = status
            self.level = level
        }
    }

    /// A status line and its colour level. Also the result of `connect` and `testProvider` jobs.
    public struct AIStatusDTO: Codable, Sendable {
        public var status: String
        public var level: String

        public init(status: String, level: String) {
            self.status = status
            self.level = level
        }
    }

    /// Result of `update(...)`: the new settings, the status that action produced (if any),
    /// and the id of the model-list refresh it started (if any).
    public struct AIUpdateDTO: Codable, Sendable {
        public var settings: AISettingsDTO
        public var status: String?
        public var level: String?
        public var refreshJobID: String?

        public init(settings: AISettingsDTO, status: String?, level: String?, refreshJobID: String?) {
            self.settings = settings
            self.status = status
            self.level = level
            self.refreshJobID = refreshJobID
        }
    }

    /// Result of a model-list refresh job.
    public struct AIModelsResultDTO: Codable, Sendable {
        public var models: [String]
        public var selectedModel: String
        /// "Model list refreshed." for a refresh the user asked for; empty when the refresh followed another action.
        public var status: String
        public var level: String

        public init(models: [String], selectedModel: String, status: String, level: String) {
            self.models = models
            self.selectedModel = selectedModel
            self.status = status
            self.level = level
        }
    }

    /// Result of a prompt import.
    public struct AIPromptImportDTO: Codable, Sendable {
        public var added: Int
        public var skipped: Int
        public var status: String
        public var level: String

        public init(added: Int, skipped: Int, status: String, level: String) {
            self.added = added
            self.skipped = skipped
            self.status = status
            self.level = level
        }
    }

    // MARK: - Shared state

    private static let lock = NSLock()
    private static var lastStatus = AIStatusDTO(status: "", level: "info")
    /// Live model lists per provider id, as the last refresh left them.
    private static var modelCache: [String: [String]] = [:]

    private static let ollamaPlaceholder = OpenRouterClient.ollamaBaseURLString
    private static let customMarker = "  (custom)"
    private static let builtinMarker = "  (built-in)"

    // MARK: - Queries

    /// The whole settings state. Like the window, it falls back to OpenRouter when the stored provider no longer exists.
    public static func state() -> AISettingsDTO {
        lock.lock()
        defer { lock.unlock() }
        return snapshot()
    }

    /// Every provider, built-in first, in the order the dropdown lists them.
    public static func providers() -> [AIProviderDTO] {
        ProviderStore.shared.providers.map(providerDTO)
    }

    /// Every prompt template, in the order the dropdown lists them.
    public static func prompts() -> [AIPromptDTO] {
        PromptStore.shared.prompts.map(promptDTO)
    }

    // MARK: - Provider and model selection

    /// Changes the selected provider, the Ollama server, the API key or the model. Any change of
    /// provider or server starts a model-list refresh, whose job id is returned as `refreshJobID`.
    /// An invalid server URL is reported as an `error` status, not thrown.
    public static func update(providerID: String? = nil, model: String? = nil, apiKey: String? = nil,
                              serverURL: String? = nil) throws -> AIUpdateDTO {
        let client = OpenRouterClient.shared
        lock.lock()
        defer { lock.unlock() }

        var status: AIStatusDTO?
        var needsRefresh = false

        if let providerID = providerID, providerID != client.providerID {
            guard let newProvider = ProviderStore.shared.provider(id: providerID) else {
                throw KarmaServiceError.notFound("No provider with id \(providerID).")
            }
            client.provider = newProvider
            status = newProvider.isOllama
                ? AIStatusDTO(status: "Using Ollama at \(client.ollamaServerURLString)", level: "info")
                : AIStatusDTO(status: "Using \(newProvider.name)", level: "info")
            needsRefresh = true
        }

        if let serverURL = serverURL, client.provider.isOllama {
            if let normalized = ProviderStore.normalizeBaseURL(serverURL) {
                if normalized != client.ollamaServerURLString {
                    client.ollamaServerURLString = normalized
                }
                status = AIStatusDTO(status: "Ollama server set to \(client.ollamaServerURLString)", level: "info")
                needsRefresh = true
            } else {
                status = AIStatusDTO(status: invalidServerText, level: "error")
            }
        }

        if let apiKey = apiKey {
            client.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let model = model {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw KarmaServiceError.invalid("Choose a model.") }
            client.selectedModel = trimmed
        }

        if let status = status {
            lastStatus = status
        }

        var refreshJobID: String?
        if needsRefresh {
            refreshJobID = startRefresh(for: client.provider, announce: false)
        }
        return AIUpdateDTO(settings: snapshot(), status: status?.status, level: status?.level,
                           refreshJobID: refreshJobID)
    }

    /// Re-fetches the model list of the selected provider (the Refresh button). The job result is an `AIModelsResultDTO`.
    public static func refreshModels() -> String {
        lock.lock()
        defer { lock.unlock() }
        return startRefresh(for: OpenRouterClient.shared.provider, announce: true)
    }

    /// The Connect button: validates the server URL and key, saves the key, then checks the endpoint
    /// (Ollama: list models; a user endpoint: list models and run a test completion; OpenRouter: GET /key).
    /// The job result is an `AIStatusDTO`. Validation failures complete the job with an `error` status.
    public static func connect(apiKey: String, serverURL: String? = nil) -> String {
        KarmaJobCenter.shared.start(kind: "ai-connect") { _ in
            let status = performConnect(apiKey: apiKey, serverURL: serverURL)
            lock.lock()
            lastStatus = status
            lock.unlock()
            return KarmaJSON.data(status)
        }
    }

    // MARK: - Endpoint manager

    /// Adds a user endpoint. Validation follows the editor sheet: name, uniqueness, base URL, then key.
    public static func addProvider(name: String, baseURL: String, requiresAPIKey: Bool, apiKey: String) throws -> AISettingsDTO {
        let validated = try validateProvider(name: name, baseURL: baseURL, requiresAPIKey: requiresAPIKey,
                                             apiKey: apiKey, excludingID: nil)
        let id = "custom.\(UUID().uuidString)"
        UserDefaults.standard.set(validated.key, forKey: "AI.\(id).apiKey")
        let provider = AIProviderConfig(id: id, name: validated.name, baseURL: validated.baseURL,
                                        requiresAPIKey: requiresAPIKey, isBuiltin: false)
        ProviderStore.shared.add(provider)
        return finishManagerAction(status: "Saved \(validated.name).")
    }

    /// Edits a user endpoint. Built-in presets cannot be edited here.
    public static func updateProvider(id: String, name: String, baseURL: String, requiresAPIKey: Bool,
                                      apiKey: String) throws -> AISettingsDTO {
        guard let existing = ProviderStore.shared.provider(id: id) else {
            throw KarmaServiceError.notFound("No provider with id \(id).")
        }
        guard !existing.isBuiltin else {
            throw KarmaServiceError.invalid("The built-in providers cannot be edited here.")
        }
        let validated = try validateProvider(name: name, baseURL: baseURL, requiresAPIKey: requiresAPIKey,
                                             apiKey: apiKey, excludingID: id)
        UserDefaults.standard.set(validated.key, forKey: "AI.\(id).apiKey")
        ProviderStore.shared.update(AIProviderConfig(id: id, name: validated.name, baseURL: validated.baseURL,
                                                     requiresAPIKey: requiresAPIKey, isBuiltin: false))
        return finishManagerAction(status: "Saved \(validated.name).")
    }

    /// Removes a user endpoint along with its key and model. A removed selected endpoint falls back to OpenRouter.
    public static func deleteProvider(id: String) throws -> AISettingsDTO {
        guard let provider = ProviderStore.shared.provider(id: id) else {
            throw KarmaServiceError.notFound("No provider with id \(id).")
        }
        guard !provider.isBuiltin else {
            throw KarmaServiceError.invalid("The built-in providers cannot be removed.")
        }
        ProviderStore.shared.remove(id: id)
        UserDefaults.standard.removeObject(forKey: "AI.\(id).apiKey")
        UserDefaults.standard.removeObject(forKey: "AI.\(id).model")
        lock.lock()
        modelCache[id] = nil
        if OpenRouterClient.shared.providerID == id {
            OpenRouterClient.shared.provider = .openRouter
        }
        lock.unlock()
        return finishManagerAction(status: "Removed \(provider.name).")
    }

    /// Checks an endpoint with its saved key and model. The job result is an `AIStatusDTO`.
    public static func testProvider(id: String) throws -> String {
        guard let provider = ProviderStore.shared.provider(id: id) else {
            throw KarmaServiceError.notFound("No provider with id \(id).")
        }
        let key = UserDefaults.standard.string(forKey: "AI.\(provider.id).apiKey") ?? ""
        let model = UserDefaults.standard.string(forKey: "AI.\(provider.id).model") ?? ""
        let urlString = provider.isOllama ? OpenRouterClient.shared.ollamaServerURLString : provider.baseURL
        guard let url = URL(string: urlString) else {
            throw KarmaServiceError.invalid("Invalid base URL.")
        }
        return KarmaJobCenter.shared.start(kind: "ai-provider-test") { _ in
            let client = OpenRouterClient.shared
            let outcome: Result<Int, Error>? = blocking { done in
                client.testConnection(name: provider.name, baseURL: url, apiKey: key,
                                      model: model.isEmpty ? nil : model,
                                      requiresAPIKey: provider.requiresAPIKey) { done($0) }
            }
            let status: AIStatusDTO
            switch outcome {
            case .success(let count)?:
                status = AIStatusDTO(status: "\(provider.name) OK — \(count) model(s) available.", level: "success")
            case .failure(let error)?:
                status = AIStatusDTO(status: "\(provider.name): \(error.localizedDescription)", level: "error")
            case nil:
                status = AIStatusDTO(status: "\(provider.name): the request timed out.", level: "error")
            }
            return KarmaJSON.data(status)
        }
    }

    // MARK: - Prompt templates

    /// Adds a prompt template. The title is required; both fields are trimmed.
    public static func addPrompt(title: String, promptText: String) throws -> AISettingsDTO {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw KarmaServiceError.invalid("Enter a title for the prompt.") }
        PromptStore.shared.add(title: trimmedTitle, promptText: promptText.trimmingCharacters(in: .whitespacesAndNewlines))
        return snapshotLocked()
    }

    /// Edits a prompt template.
    public static func updatePrompt(id: String, title: String, promptText: String) throws -> AISettingsDTO {
        guard PromptStore.shared.prompt(id: id) != nil else {
            throw KarmaServiceError.notFound("No prompt with id \(id).")
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw KarmaServiceError.invalid("Enter a title for the prompt.") }
        PromptStore.shared.update(id: id, title: trimmedTitle,
                                  promptText: promptText.trimmingCharacters(in: .whitespacesAndNewlines))
        return snapshotLocked()
    }

    /// Removes a prompt template. The confirmation ("Remove \"<title>\" from the saved prompts?") is the caller's.
    public static func deletePrompt(id: String) throws -> AISettingsDTO {
        guard PromptStore.shared.prompt(id: id) != nil else {
            throw KarmaServiceError.notFound("No prompt with id \(id).")
        }
        PromptStore.shared.remove(id: id)
        return snapshotLocked()
    }

    /// The JSON export of every prompt template, named as the save panel names it.
    public static func exportPrompts() -> (fileName: String, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        let count = PromptStore.shared.prompts.count
        lastStatus = AIStatusDTO(status: "Exported \(count) prompt templates.", level: "success")
        return ("KarmaPro-Prompts.json", PromptStore.shared.exportData())
    }

    /// Adds the prompts of an export file, skipping duplicates. Invalid data throws with the window's message.
    public static func importPrompts(data: Data) throws -> AIPromptImportDTO {
        lock.lock()
        defer { lock.unlock() }
        let result = PromptStore.shared.importData(data)
        if let error = result.error {
            lastStatus = AIStatusDTO(status: error, level: "error")
            throw KarmaServiceError.invalid(error)
        }
        let text = "Imported \(result.added) prompt(s), skipped \(result.skipped) duplicate(s)."
        let level = result.added > 0 ? "success" : "info"
        lastStatus = AIStatusDTO(status: text, level: level)
        return AIPromptImportDTO(added: result.added, skipped: result.skipped, status: text, level: level)
    }

    // MARK: - Private: state

    private static let invalidServerText = "Invalid server URL — e.g. http://localhost:11434/v1"

    /// Caller must hold `lock`.
    private static func snapshot() -> AISettingsDTO {
        let client = OpenRouterClient.shared
        if ProviderStore.shared.provider(id: client.providerID) == nil {
            client.provider = .openRouter
        }
        let provider = client.provider
        return AISettingsDTO(
            providers: ProviderStore.shared.providers.map(providerDTO),
            selectedProviderID: provider.id,
            requiresAPIKey: provider.requiresAPIKey,
            isOllama: provider.isOllama,
            apiKey: client.apiKey,
            serverURL: client.ollamaServerURLString,
            serverPlaceholder: ollamaPlaceholder,
            models: modelList(for: provider),
            selectedModel: client.selectedModel,
            prompts: PromptStore.shared.prompts.map(promptDTO),
            status: lastStatus.status,
            level: lastStatus.level)
    }

    private static func snapshotLocked() -> AISettingsDTO {
        lock.lock()
        defer { lock.unlock() }
        return snapshot()
    }

    private static func finishManagerAction(status: String) -> AISettingsDTO {
        lock.lock()
        lastStatus = AIStatusDTO(status: status, level: "success")
        lock.unlock()
        return snapshotLocked()
    }

    private static func providerDTO(_ provider: AIProviderConfig) -> AIProviderDTO {
        let url = provider.isOllama ? OpenRouterClient.shared.ollamaServerURLString : provider.baseURL
        return AIProviderDTO(
            id: provider.id,
            name: provider.name,
            baseURL: url,
            requiresAPIKey: provider.requiresAPIKey,
            isBuiltin: provider.isBuiltin,
            isOllama: provider.isOllama,
            popupTitle: provider.isBuiltin ? provider.name : provider.name + customMarker,
            tableName: provider.isBuiltin ? provider.name + builtinMarker : provider.name,
            tableKey: provider.requiresAPIKey ? "required" : "none")
    }

    private static func promptDTO(_ template: PromptTemplate) -> AIPromptDTO {
        AIPromptDTO(id: template.id, title: template.title, promptText: template.promptText,
                    isBuiltin: template.isBuiltin)
    }

    /// The popup's model items for `provider`: the live list if one was fetched, else the fallbacks
    /// (or the saved model alone), with the saved model always present and selected.
    /// Caller must hold `lock`.
    private static func modelList(for provider: AIProviderConfig) -> [String] {
        let saved = OpenRouterClient.shared.selectedModel
        let base: [String]
        if let cached = modelCache[provider.id] {
            base = cached
        } else {
            let fallbacks = provider.fallbackModels
            base = fallbacks.isEmpty ? (saved.isEmpty ? [] : [saved]) : fallbacks
        }
        return withSelected(base, selected: saved)
    }

    /// The saved model is inserted at the top when the list lacks it, as `applyModelItems` does.
    private static func withSelected(_ items: [String], selected: String) -> [String] {
        if items.contains(selected) || selected.isEmpty { return items }
        return [selected] + items
    }

    // MARK: - Private: refresh

    /// Applies the fallback list at once and fetches the live list in a job. Caller must hold `lock`.
    private static func startRefresh(for provider: AIProviderConfig, announce: Bool) -> String {
        let client = OpenRouterClient.shared
        let saved = client.selectedModel
        let fallbacks = provider.fallbackModels
        let base = fallbacks.isEmpty ? (saved.isEmpty ? [] : [saved]) : fallbacks
        modelCache[provider.id] = base
        if announce {
            lastStatus = AIStatusDTO(status: "Model list refreshed.", level: "info")
        }
        let needsKey = provider.requiresAPIKey
        let hasKey = !client.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let statusText = announce ? "Model list refreshed." : ""
        return KarmaJobCenter.shared.start(kind: "ai-models") { _ in
            if !(needsKey && !hasKey) {
                fetchAndCache(provider: provider)
            }
            lock.lock()
            let models = modelList(for: provider)
            let selected = OpenRouterClient.shared.selectedModel
            lock.unlock()
            return KarmaJSON.data(AIModelsResultDTO(models: models, selectedModel: selected,
                                                    status: statusText, level: "info"))
        }
    }

    /// Fetches the live model list of `provider` (only the selected provider's key and base URL apply)
    /// and stores the sorted ids as its model list.
    private static func fetchAndCache(provider: AIProviderConfig) {
        let client = OpenRouterClient.shared
        let models: [OpenRouterModel]? = blocking { done in client.fetchModels { done($0) } }
        guard let live = models, !live.isEmpty else { return }
        lock.lock()
        modelCache[provider.id] = live.map { $0.id }.sorted()
        lock.unlock()
    }

    // MARK: - Private: connect

    /// Mirrors `AIWindowController.connectClicked` and returns the status it would show.
    private static func performConnect(apiKey: String, serverURL: String?) -> AIStatusDTO {
        let client = OpenRouterClient.shared
        lock.lock()
        if client.provider.isOllama, let serverURL = serverURL {
            if let normalized = ProviderStore.normalizeBaseURL(serverURL) {
                if normalized != client.ollamaServerURLString {
                    client.ollamaServerURLString = normalized
                }
            } else {
                lock.unlock()
                return AIStatusDTO(status: invalidServerText, level: "error")
            }
        }
        lock.unlock()

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = client.provider
        if client.requiresAPIKey && key.isEmpty {
            return AIStatusDTO(status: "Enter your \(provider.name) API key first.", level: "error")
        }
        client.apiKey = key

        if client.isOllama {
            let host = client.baseURL.host ?? client.ollamaServerURLString
            let models: [OpenRouterModel]? = blocking { done in client.fetchModels { done($0) } }
            guard let list = models, !list.isEmpty else {
                return AIStatusDTO(status: "Could not reach Ollama at \(host) — is the server running? " +
                                   "Launch the Ollama app or run `ollama serve`.", level: "error")
            }
            lock.lock()
            modelCache[provider.id] = list.map { $0.id }.sorted()
            lock.unlock()
            return AIStatusDTO(status: "Connected to Ollama — \(list.count) model(s) available.", level: "success")
        }

        if provider.id != AIProviderConfig.openRouter.id {
            let name = provider.name
            let outcome: Result<Int, Error>? = blocking { done in
                client.testConnection(name: name, baseURL: client.baseURL, apiKey: key,
                                      model: client.selectedModel, requiresAPIKey: client.requiresAPIKey) { done($0) }
            }
            switch outcome {
            case .success(let count)?:
                fetchAndCache(provider: provider)
                return AIStatusDTO(status: "Connected to \(name) — \(count) model(s) available.", level: "success")
            case .failure(let error)?:
                return AIStatusDTO(status: "\(name): \(error.localizedDescription)", level: "error")
            case nil:
                return AIStatusDTO(status: "\(name): the request timed out.", level: "error")
            }
        }

        var request = URLRequest(url: client.baseURL.appendingPathComponent("key"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let response: (Data?, URLResponse?, Error?)? = blocking { done in
            URLSession.shared.dataTask(with: request) { data, response, error in
                done((data, response, error))
            }.resume()
        }
        guard let response = response else {
            return AIStatusDTO(status: "Could not reach openrouter.ai — key saved anyway.", level: "warning")
        }
        let (data, urlResponse, error) = response
        if let http = urlResponse as? HTTPURLResponse, http.statusCode == 401 {
            return AIStatusDTO(status: "OpenRouter rejected this API key.", level: "error")
        }
        guard error == nil, data != nil else {
            return AIStatusDTO(status: "Could not reach openrouter.ai — key saved anyway.", level: "warning")
        }
        fetchAndCache(provider: provider)
        return AIStatusDTO(status: "Connected to OpenRouter.", level: "success")
    }

    // MARK: - Private: validation and blocking

    /// The editor sheet's checks, in its order. Returns the trimmed name, the normalised URL and the key.
    private static func validateProvider(name: String, baseURL: String, requiresAPIKey: Bool, apiKey: String,
                                         excludingID: String?) throws
        -> (name: String, baseURL: String, key: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw KarmaServiceError.invalid("Enter a name for this provider.") }
        guard !ProviderStore.shared.nameExists(trimmedName, excluding: excludingID) else {
            throw KarmaServiceError.invalid("Another provider already uses the name \"\(trimmedName)\".")
        }
        guard let normalized = ProviderStore.normalizeBaseURL(baseURL) else {
            throw KarmaServiceError.invalid("Enter a valid base URL, e.g. https://api.example.com/v1")
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if requiresAPIKey && key.isEmpty {
            throw KarmaServiceError.invalid("This endpoint requires an API key.")
        }
        return (trimmedName, normalized, key)
    }

    /// Runs an asynchronous call and waits for its completion on the calling (job) thread.
    /// Returns nil if the completion does not arrive within two minutes.
    private static func blocking<T>(_ start: (@escaping (T) -> Void) -> Void) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var value: T?
        start { result in
            value = result
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 120) == .success else { return nil }
        return value
    }
}
