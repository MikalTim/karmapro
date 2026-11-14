// Pure rules for the AI window's provider and prompt controls: what each
// dropdown lists, which buttons are enabled, what a template paste produces and
// the status texts the AppKit controllers set.
import type { AIPrompt, AIProvider } from "./types";

/** The provider dropdown item that opens the endpoint manager instead of switching providers. */
export const ADD_CUSTOM_PROVIDER = "__add_custom__";
const ADD_CUSTOM_TITLE = "Add custom...";
const NO_PROMPTS_TITLE = "(no saved prompts)";

export interface MenuItem {
  title: string;
  value: string;
  disabled?: boolean;
}

export function providerPopupItems(providers: readonly AIProvider[]): MenuItem[] {
  return [
    ...providers.map((provider) => ({ title: provider.popupTitle, value: provider.id })),
    { title: ADD_CUSTOM_TITLE, value: ADD_CUSTOM_PROVIDER },
  ];
}

export interface ProviderRow {
  id: string;
  name: string;
  url: string;
  key: string;
  builtin: boolean;
}

/** The endpoint table's rows: the name and key columns come from the server's table texts. */
export function providerRows(providers: readonly AIProvider[]): ProviderRow[] {
  return providers.map((provider) => ({
    id: provider.id,
    name: provider.tableName,
    url: provider.baseURL,
    key: provider.tableKey,
    builtin: provider.isBuiltin,
  }));
}

/** Edit and Remove need a user endpoint (the presets are fixed); Test needs any selection. */
export function providerButtons(selected: AIProvider | null): { edit: boolean; remove: boolean; test: boolean } {
  const editable = selected !== null && !selected.isBuiltin;
  return { edit: editable, remove: editable, test: selected !== null };
}

/** The provider the endpoint table has selected, or null. */
export function selectedProvider(providers: readonly AIProvider[], selectedID: string | null): AIProvider | null {
  if (selectedID === null) return null;
  return providers.find((provider) => provider.id === selectedID) ?? null;
}

/**
 * The prompt dropdown's items. With no templates it shows one disabled item,
 * and the dropdown and the Edit and Remove buttons are disabled.
 */
export function promptPopupItems(prompts: readonly AIPrompt[]): { items: MenuItem[]; enabled: boolean } {
  if (prompts.length === 0) {
    return { items: [{ title: NO_PROMPTS_TITLE, value: "", disabled: true }], enabled: false };
  }
  return { items: prompts.map((prompt) => ({ title: prompt.title, value: prompt.id })), enabled: true };
}

/**
 * The template the dropdown shows: the chosen one while it exists, else the
 * first, as an NSPopUpButton selects its first item by default.
 */
export function effectivePromptID(prompts: readonly AIPrompt[], selectedID: string | null): string | null {
  if (selectedID !== null && prompts.some((prompt) => prompt.id === selectedID)) return selectedID;
  return prompts[0]?.id ?? null;
}

export interface TextSelection {
  start: number;
  end: number;
}

/**
 * Where a chosen template's text goes in the prompt editor
 * (`AIWindowController.promptSelected`). An empty editor takes the text; a caret
 * at the end (or no caret yet) adds it after a blank line; otherwise the text
 * replaces the selection, or is inserted at the caret.
 */
export function insertTemplate(current: string, template: string, selection: TextSelection | null): string {
  if (current === "") return template;
  const start = selection ? selection.start : current.length;
  if (start >= current.length) return `${current}\n\n${template}`;
  const end = selection ? Math.max(start, selection.end) : start;
  return current.slice(0, start) + template + current.slice(end);
}

/** The host name of a server URL, as the connect message shows it; the text itself when it does not parse. */
export function hostOf(url: string): string {
  try {
    return new URL(url).hostname || url;
  } catch {
    return url;
  }
}

/** The status shown while a connect check runs (`AIWindowController.connectClicked`). */
export function connectingStatus(provider: Pick<AIProvider, "name" | "isOllama">, serverURL: string): string {
  return provider.isOllama ? `Connecting to Ollama at ${hostOf(serverURL)}\u2026` : `Connecting to ${provider.name}\u2026`;
}

export function exportedStatus(count: number): string {
  return `Exported ${count} prompt templates.`;
}

export function exportFailedStatus(message: string): string {
  return `Export failed: ${message}`;
}

export function removeProviderMessage(name: string): string {
  return `Remove "${name}" and its saved API key?`;
}

export function removePromptMessage(title: string): string {
  return `Remove "${title}" from the saved prompts?`;
}

/** Whether the server URL field must be saved before a request: only for Ollama, and only when edited. */
export function serverNeedsSaving(isOllama: boolean, draft: string, stored: string): boolean {
  return isOllama && draft !== stored;
}
