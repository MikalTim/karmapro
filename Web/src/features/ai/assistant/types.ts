// The AI assistant's JSON replies, as the server sends them (see
// Sources/KarmaCore/service/AISettingsService.swift and AIChatService.swift).
// Levels are plain strings: "info", "error", "warning" or "success" for
// settings, and "info" or "error" for the chat.

export interface AIProvider {
  id: string;
  name: string;
  baseURL: string;
  requiresAPIKey: boolean;
  isBuiltin: boolean;
  isOllama: boolean;
  /** Dropdown title: the name, with "  (custom)" for user endpoints. */
  popupTitle: string;
  /** Endpoint table name column: the name, with "  (built-in)" for presets. */
  tableName: string;
  /** Endpoint table key column: "required" or "none". */
  tableKey: string;
}

export interface AIPrompt {
  id: string;
  title: string;
  promptText: string;
  isBuiltin: boolean;
}

export interface AISettings {
  providers: AIProvider[];
  selectedProviderID: string;
  requiresAPIKey: boolean;
  isOllama: boolean;
  apiKey: string;
  serverURL: string;
  serverPlaceholder: string;
  models: string[];
  selectedModel: string;
  prompts: AIPrompt[];
  status: string;
  level: string;
}

export interface AIStatus {
  status: string;
  level: string;
}

/** Reply of PUT /api/ai/settings. */
export interface AIUpdate {
  settings: AISettings;
  status?: string;
  level?: string;
  refreshJobID?: string;
}

/** Result of a model-list refresh job. */
export interface AIModelsResult {
  models: string[];
  selectedModel: string;
  status: string;
  level: string;
}

/** Reply of POST /api/ai/prompts/import. */
export interface AIPromptImport {
  added: number;
  skipped: number;
  status: string;
  level: string;
}

export interface AIChatEntry {
  /** "turn" (the dim "> prompt" marker), "tool" or "answer". */
  kind: "turn" | "tool" | "answer";
  /** Turn: the marker line. Tool: the label line. Answer: the markdown text. */
  text: string;
  /** Tool only: the output as the pane shows it. */
  output?: string;
}

export interface AIChatState {
  transcript: AIChatEntry[];
  /** The answer being written, empty between rounds. */
  streaming: string;
  thinking: boolean;
  requestInFlight: boolean;
  canContinue: boolean;
  canNewChat: boolean;
  status: string;
  statusLevel: string;
  /** "Stop" while a request runs, else "Send to AI". */
  sendTitle: string;
  /** The last `ai.stream` event this state includes. */
  seq: number;
}

/** Reply of GET /api/ai. */
export interface AIOverview {
  settings: AISettings;
  chat: AIChatState;
}

/** One `ai.stream` event. `text` is JSON for "tool" events. */
export interface AIStreamEvent {
  seq: number;
  kind: string;
  text: string;
  level?: string;
}
