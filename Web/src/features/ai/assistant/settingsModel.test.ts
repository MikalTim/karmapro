import { describe, expect, it } from "vitest";
import {
  ADD_CUSTOM_PROVIDER,
  connectingStatus,
  effectivePromptID,
  exportedStatus,
  hostOf,
  insertTemplate,
  promptPopupItems,
  providerButtons,
  providerPopupItems,
  providerRows,
  removePromptMessage,
  removeProviderMessage,
  selectedProvider,
  serverNeedsSaving,
} from "./settingsModel";
import type { AIPrompt, AIProvider } from "./types";

function provider(overrides: Partial<AIProvider>): AIProvider {
  return {
    id: "custom.1",
    name: "LM Studio",
    baseURL: "http://localhost:1234/v1",
    requiresAPIKey: false,
    isBuiltin: false,
    isOllama: false,
    popupTitle: "LM Studio  (custom)",
    tableName: "LM Studio",
    tableKey: "none",
    apiKey: "",
    ...overrides,
  };
}

const openRouter = provider({
  id: "builtin.openrouter",
  name: "OpenRouter",
  baseURL: "https://openrouter.ai/api/v1",
  requiresAPIKey: true,
  isBuiltin: true,
  popupTitle: "OpenRouter",
  tableName: "OpenRouter  (built-in)",
  tableKey: "required",
});

const ollama = provider({
  id: "builtin.ollama",
  name: "Ollama",
  baseURL: "http://localhost:11434/v1",
  isBuiltin: true,
  isOllama: true,
  popupTitle: "Ollama",
  tableName: "Ollama  (built-in)",
  tableKey: "none",
});

function prompt(id: string, title: string): AIPrompt {
  return { id, title, promptText: `Text of ${title}`, isBuiltin: false };
}

describe("provider dropdown and table", () => {
  it("lists the providers by their popup titles, then the add-custom item", () => {
    const items = providerPopupItems([openRouter, ollama, provider({})]);
    expect(items.map((item) => item.title)).toEqual([
      "OpenRouter",
      "Ollama",
      "LM Studio  (custom)",
      "Add custom...",
    ]);
    expect(items[3].value).toBe(ADD_CUSTOM_PROVIDER);
  });

  it("builds the endpoint table rows from the table texts", () => {
    expect(providerRows([openRouter])).toEqual([
      { id: "builtin.openrouter", name: "OpenRouter  (built-in)", url: "https://openrouter.ai/api/v1", key: "required", builtin: true },
    ]);
  });

  it("enables Edit and Remove only for a user endpoint, and Test for any selection", () => {
    expect(providerButtons(provider({}))).toEqual({ edit: true, remove: true, test: true });
    expect(providerButtons(openRouter)).toEqual({ edit: false, remove: false, test: true });
    expect(providerButtons(null)).toEqual({ edit: false, remove: false, test: false });
  });

  it("finds the selected provider by id", () => {
    const user = provider({});
    expect(selectedProvider([openRouter, user], "custom.1")).toBe(user);
    expect(selectedProvider([openRouter, user], null)).toBeNull();
    expect(selectedProvider([openRouter, user], "missing")).toBeNull();
  });
});

describe("prompt dropdown", () => {
  it("shows a disabled placeholder and disables its buttons when there are no templates", () => {
    expect(promptPopupItems([])).toEqual({
      items: [{ title: "(no saved prompts)", value: "", disabled: true }],
      enabled: false,
    });
  });

  it("lists the templates by title", () => {
    const result = promptPopupItems([prompt("a", "Audit Auth Code"), prompt("b", "OWASP")]);
    expect(result.enabled).toBe(true);
    expect(result.items).toEqual([
      { title: "Audit Auth Code", value: "a" },
      { title: "OWASP", value: "b" },
    ]);
  });

  it("shows the chosen template, or the first when the chosen one is gone", () => {
    const prompts = [prompt("a", "A"), prompt("b", "B")];
    expect(effectivePromptID(prompts, "b")).toBe("b");
    expect(effectivePromptID(prompts, "gone")).toBe("a");
    expect(effectivePromptID(prompts, null)).toBe("a");
    expect(effectivePromptID([], null)).toBeNull();
  });
});

describe("template paste", () => {
  it("fills an empty editor with the template", () => {
    expect(insertTemplate("", "Check auth", null)).toBe("Check auth");
  });

  it("adds the template after a blank line when the caret is at the end", () => {
    expect(insertTemplate("Look at main.c", "Check auth", null)).toBe("Look at main.c\n\nCheck auth");
    expect(insertTemplate("Look at main.c", "Check auth", { start: 14, end: 14 })).toBe(
      "Look at main.c\n\nCheck auth",
    );
  });

  it("inserts at the caret inside the text", () => {
    expect(insertTemplate("ab", "X", { start: 1, end: 1 })).toBe("aXb");
  });

  it("replaces a selection", () => {
    expect(insertTemplate("hello world", "there", { start: 6, end: 11 })).toBe("hello there");
  });
});

describe("status texts", () => {
  it("names the host of an Ollama server in the connect message", () => {
    expect(connectingStatus(ollama, "http://localhost:11434/v1")).toBe("Connecting to Ollama at localhost\u2026");
  });

  it("names the endpoint in the connect message for the other providers", () => {
    expect(connectingStatus(openRouter, "")).toBe("Connecting to OpenRouter\u2026");
    expect(connectingStatus(provider({}), "")).toBe("Connecting to LM Studio\u2026");
  });

  it("falls back to the text when a server URL does not parse", () => {
    expect(hostOf("not a url")).toBe("not a url");
    expect(hostOf("http://10.0.0.5:11434/v1")).toBe("10.0.0.5");
  });

  it("writes the confirmation and export texts verbatim", () => {
    expect(removeProviderMessage("LM Studio")).toBe('Remove "LM Studio" and its saved API key?');
    expect(removePromptMessage("OWASP")).toBe('Remove "OWASP" from the saved prompts?');
    expect(exportedStatus(0)).toBe("Exported 0 prompt templates.");
    expect(exportedStatus(9)).toBe("Exported 9 prompt templates.");
  });
});

describe("server field", () => {
  it("saves the address only for Ollama and only when it changed", () => {
    expect(serverNeedsSaving(true, "http://localhost:11434/v1", "http://localhost:11434/v1")).toBe(false);
    expect(serverNeedsSaving(true, "http://10.0.0.5:11434/v1", "http://localhost:11434/v1")).toBe(true);
    expect(serverNeedsSaving(false, "http://10.0.0.5:11434/v1", "http://localhost:11434/v1")).toBe(false);
  });
});
