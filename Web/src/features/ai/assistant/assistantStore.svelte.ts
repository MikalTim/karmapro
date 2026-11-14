// The AI assistant's state in the browser. The server keeps the one
// conversation and the settings; this store mirrors them, applies the
// `ai.stream` events as they arrive, and fetches the state again when an event
// was missed or a round ended. Every action the window and the provider manager
// perform goes through here, so both read the same settings.
import { api, download, upload } from "../../../lib/api";
import { on, onConnection } from "../../../lib/events";
import { trackJob } from "../../../lib/jobs";
import { continueEnabled, reduceStreamEvent } from "./chatModel";
import {
  connectingStatus,
  exportedStatus,
  exportFailedStatus,
  insertTemplate,
  serverNeedsSaving,
  type TextSelection,
} from "./settingsModel";
import { idleStatus, type StatusLine } from "./status";
import type {
  AIChatState,
  AIModelsResult,
  AIOverview,
  AIPromptImport,
  AIProvider,
  AISettings,
  AIStatus,
  AIStreamEvent,
  AIUpdate,
} from "./types";

/** The provider fields the editor sends. */
export interface ProviderForm {
  name: string;
  baseURL: string;
  requiresAPIKey: boolean;
  apiKey: string;
}

class AssistantStore {
  /** Settings as the server last reported them. */
  settings = $state.raw<AISettings | null>(null);
  /** The conversation. Its `transcript` keeps its identity while only the answer changes. */
  chat = $state.raw<AIChatState | null>(null);
  statusLine = $state.raw<StatusLine>(idleStatus);
  /** The prompt editor's text and the fields the user is editing, which save only when used. */
  draft = $state("");
  apiKeyDraft = $state("");
  serverDraft = $state("");
  /** The template the prompt dropdown chose; see `effectivePromptID`. */
  selectedPromptID = $state<string | null>(null);
}

export const assistant = new AssistantStore();

/** Stream events not yet known to be in `assistant.chat`, in arrival order. */
let pending: AIStreamEvent[] = [];
/** Pending state fetches, run one after another; events wait while any is queued. */
let fetchesPending = 0;
let fetchQueue: Promise<void> = Promise.resolve();
/** Set after a gap triggered a fetch, so a gap that persists cannot fetch forever. */
let gapRetried = false;
let subscribed = false;
let modelsRefreshedOnOpen = false;

function setError(error: unknown): void {
  assistant.statusLine = { text: error instanceof Error ? error.message : String(error), level: "error" };
}

function setStatus(text: string, level: string): void {
  assistant.statusLine = { text, level };
}

/** Subscribes to the stream and loads the state, once. Called when the first AI window opens. */
export function startAssistant(): void {
  if (subscribed) return;
  subscribed = true;
  on<AIStreamEvent>("ai.stream", (event) => {
    pending.push(event);
    drain();
  });
  // A reconnect may follow a server restart, whose sequence numbers start again, so that state is taken as it is.
  onConnection((open) => {
    if (open) void refresh(true);
  });
  void refresh(false);
}

/** Fetches the settings and the conversation, one fetch at a time. */
export function refresh(authoritative: boolean): Promise<void> {
  fetchesPending += 1;
  fetchQueue = fetchQueue.then(async () => {
    await fetchOverview(authoritative);
    fetchesPending -= 1;
    drain();
  });
  return fetchQueue;
}

async function fetchOverview(authoritative: boolean): Promise<void> {
  try {
    const overview = await api<AIOverview>("GET", "/api/ai");
    const first = assistant.settings === null;
    assistant.settings = overview.settings;
    if (first) {
      resetDrafts(overview.settings);
      assistant.statusLine =
        overview.chat.status !== ""
          ? { text: overview.chat.status, level: overview.chat.statusLevel }
          : { text: overview.settings.status, level: overview.settings.level };
    }
    adoptChat(overview.chat, authoritative);
  } catch (error) {
    setError(error);
  }
}

/**
 * Takes a state the server sent. A reply to an action can arrive after newer
 * events were applied, so it replaces the state only when it is at least as new.
 */
function adoptChat(state: AIChatState, authoritative: boolean): boolean {
  if (!authoritative && assistant.chat !== null && state.seq < assistant.chat.seq) return false;
  assistant.chat = state;
  return true;
}

/** Applies the events that the current state does not yet include. */
function drain(): void {
  if (assistant.chat === null || fetchesPending > 0) return;
  while (pending.length > 0) {
    const event = pending[0];
    const step = reduceStreamEvent(assistant.chat, event);
    if (step.kind === "stale") {
      pending.shift();
      continue;
    }
    if (step.kind === "gap") {
      if (gapRetried) {
        // The server has already sent the state after this gap, so the event cannot be recovered.
        gapRetried = false;
        pending.shift();
        continue;
      }
      gapRetried = true;
      void refresh(false);
      return;
    }
    pending.shift();
    if (step.kind === "refetch") {
      void refresh(false);
      return;
    }
    gapRetried = false;
    assistant.chat = step.state;
    if (event.kind === "status" || event.kind === "error") {
      setStatus(event.text, step.state.statusLevel);
    }
  }
}

/** Takes the state a chat action answered with. */
function adoptResponse(state: AIChatState): void {
  if (adoptChat(state, false) && state.status !== "") setStatus(state.status, state.statusLevel);
  drain();
}

async function postChat(path: string, body?: unknown): Promise<AIChatState | null> {
  try {
    const state = await api<AIChatState>("POST", path, body);
    adoptResponse(state);
    return state;
  } catch (error) {
    setError(error);
    return null;
  }
}

function resetDrafts(settings: AISettings): void {
  assistant.apiKeyDraft = settings.apiKey;
  assistant.serverDraft = settings.serverURL;
}

/**
 * Saves the server field before a request, as `syncServer` does for Ollama.
 * Returns false when the address is refused, which stops the request.
 */
async function syncServerField(announce: boolean): Promise<boolean> {
  const settings = assistant.settings;
  if (!settings) return true;
  const draft = assistant.serverDraft.trim();
  if (!serverNeedsSaving(settings.isOllama, draft, settings.serverURL)) return true;
  return saveServerURL(draft, announce);
}

/**
 * Sends the prompt editor's text (the Send button). While a request runs it
 * stops that request instead, and the text stays in the editor.
 */
export async function sendPrompt(): Promise<void> {
  const chat = assistant.chat;
  if (!chat) return;
  const stopping = chat.requestInFlight;
  if (!stopping && assistant.draft.trim() !== "" && !(await syncServerField(false))) return;
  const state = await postChat("/api/ai/chat/send", { text: assistant.draft });
  if (state && !stopping && state.statusLevel !== "error") assistant.draft = "";
}

/** A ready-made question, sent like the Send button does. */
export async function ask(question: string): Promise<void> {
  assistant.draft = question;
  await sendPrompt();
}

export async function continueChat(): Promise<void> {
  const chat = assistant.chat;
  if (!chat || !continueEnabled(chat)) return;
  if (!(await syncServerField(false))) return;
  await postChat("/api/ai/chat/continue");
}

export async function newChat(): Promise<void> {
  await postChat("/api/ai/chat/new");
}

export async function stopChat(): Promise<void> {
  await postChat("/api/ai/chat/stop");
}

/** Stops a request that is still running when the window closes. */
export function stopIfRunning(): void {
  if (assistant.chat?.requestInFlight) void stopChat();
}

/**
 * Saves the Ollama server address (the field's Return key, or a send).
 * An invalid address is reported and the field keeps the text.
 */
export async function saveServerURL(url: string, announce: boolean): Promise<boolean> {
  try {
    const update = await api<AIUpdate>("PUT", "/api/ai/settings", { serverURL: url });
    assistant.settings = update.settings;
    const failed = update.level === "error";
    if (!failed) assistant.serverDraft = update.settings.serverURL;
    if (update.status !== undefined && (announce || failed)) setStatus(update.status, update.level ?? "info");
    if (update.refreshJobID !== undefined) void followModels(update.refreshJobID, false);
    return !failed;
  } catch (error) {
    setError(error);
    return false;
  }
}

/** Changes the provider. The model list then refreshes, and its status line is set by the server. */
export async function selectProvider(id: string): Promise<void> {
  try {
    const update = await api<AIUpdate>("PUT", "/api/ai/settings", { providerID: id });
    assistant.settings = update.settings;
    resetDrafts(update.settings);
    if (update.status !== undefined) setStatus(update.status, update.level ?? "info");
    if (update.refreshJobID !== undefined) void followModels(update.refreshJobID, false);
  } catch (error) {
    setError(error);
  }
}

export async function selectModel(model: string): Promise<void> {
  try {
    const update = await api<AIUpdate>("PUT", "/api/ai/settings", { model });
    assistant.settings = update.settings;
  } catch (error) {
    setError(error);
  }
}

/** Asks the server for the model list and shows it when the job finishes. */
export async function refreshModels(announce: boolean): Promise<void> {
  try {
    const { jobId } = await api<{ jobId: string }>("POST", "/api/ai/models/refresh");
    await followModels(jobId, announce);
  } catch (error) {
    setError(error);
  }
}

/** The first time the window opens, the model list is refreshed, as `AIWindowController.init` does. */
export function refreshModelsOnFirstOpen(): void {
  if (modelsRefreshedOnOpen) return;
  modelsRefreshedOnOpen = true;
  void refreshModels(false);
}

async function followModels(jobId: string, announce: boolean): Promise<void> {
  try {
    const outcome = await trackJob<AIModelsResult>(jobId).promise;
    const result = outcome.result;
    if (!result) return;
    if (assistant.settings) assistant.settings = { ...assistant.settings, models: result.models };
    if (announce) setStatus(result.status, result.level);
  } catch (error) {
    setError(error);
  }
}

/** Connect: checks the endpoint and saves the key (the server does both). */
export async function connect(): Promise<void> {
  const settings = assistant.settings;
  if (!settings) return;
  const serverURL = settings.isOllama ? assistant.serverDraft.trim() : undefined;
  const provider = settings.providers.find((candidate) => candidate.id === settings.selectedProviderID);
  if (provider) setStatus(connectingStatus(provider, serverURL ?? settings.serverURL), "info");
  try {
    const { jobId } = await api<{ jobId: string }>("POST", "/api/ai/connect", {
      apiKey: assistant.apiKeyDraft,
      serverURL,
    });
    const outcome = await trackJob<AIStatus>(jobId).promise;
    if (outcome.result) setStatus(outcome.result.status, outcome.result.level);
    await refresh(false);
  } catch (error) {
    setError(error);
  }
}

/** Replaces the provider list after a change in the endpoint manager; the selection and key fields follow it. */
function adoptProviderSettings(settings: AISettings): void {
  assistant.settings = settings;
  resetDrafts(settings);
  void refreshModels(false);
}

export function saveProvider(existing: AIProvider | null, form: ProviderForm): Promise<AISettings> {
  const request = existing
    ? api<AISettings>("PUT", `/api/ai/providers/${encodeURIComponent(existing.id)}`, form)
    : api<AISettings>("POST", "/api/ai/providers", form);
  return request.then((settings) => {
    adoptProviderSettings(settings);
    return settings;
  });
}

/** The saved key of a user endpoint, read when its edit sheet opens (the settings reply carries no endpoint keys). */
export async function loadProviderKey(id: string): Promise<string> {
  const stored = await api<{ apiKey: string }>("GET", `/api/ai/providers/${encodeURIComponent(id)}/key`);
  return stored.apiKey;
}

export function deleteProvider(id: string): Promise<AISettings> {
  return api<AISettings>("DELETE", `/api/ai/providers/${encodeURIComponent(id)}`).then((settings) => {
    adoptProviderSettings(settings);
    return settings;
  });
}

/** Runs the endpoint's check and returns its status, or null when the job produced none. */
export async function testProvider(id: string): Promise<AIStatus | null> {
  const { jobId } = await api<{ jobId: string }>("POST", `/api/ai/providers/${encodeURIComponent(id)}/test`);
  const outcome = await trackJob<AIStatus>(jobId).promise;
  return outcome.result ?? null;
}

/** Adds a template and selects it, as `AIWindowController.showPromptEditor` does. */
export async function addPrompt(title: string, promptText: string): Promise<void> {
  const settings = await api<AISettings>("POST", "/api/ai/prompts", { title, promptText });
  assistant.settings = settings;
  // The server appends new templates, so the last one is the new template.
  assistant.selectedPromptID = settings.prompts.at(-1)?.id ?? null;
}

export async function updatePrompt(id: string, title: string, promptText: string): Promise<void> {
  const settings = await api<AISettings>("PUT", `/api/ai/prompts/${encodeURIComponent(id)}`, { title, promptText });
  assistant.settings = settings;
}

export async function deletePrompt(id: string): Promise<void> {
  const settings = await api<AISettings>("DELETE", `/api/ai/prompts/${encodeURIComponent(id)}`);
  assistant.settings = settings;
  if (assistant.selectedPromptID === id) assistant.selectedPromptID = null;
}

/** Pastes a chosen template into the prompt editor. */
export function choosePrompt(id: string, selection: TextSelection | null): void {
  const prompt = assistant.settings?.prompts.find((candidate) => candidate.id === id);
  if (!prompt) return;
  assistant.selectedPromptID = id;
  assistant.draft = insertTemplate(assistant.draft, prompt.promptText, selection);
}

export async function exportPrompts(): Promise<void> {
  try {
    await download("/api/ai/prompts/export", { fallbackName: "KarmaPro-Prompts.json" });
    setStatus(exportedStatus(assistant.settings?.prompts.length ?? 0), "success");
  } catch (error) {
    setStatus(exportFailedStatus(error instanceof Error ? error.message : String(error)), "error");
  }
}

/** Adds the templates of an export file, skipping duplicates. The server's text is the status. */
export async function importPrompts(file: File): Promise<void> {
  try {
    const result = await upload<AIPromptImport>("/api/ai/prompts/import", file);
    setStatus(result.status, result.level);
  } catch (error) {
    setError(error);
  }
  await refresh(false);
}

/** Shows an action's failure on the status line, as the window reports it. */
export { setError as reportError };
