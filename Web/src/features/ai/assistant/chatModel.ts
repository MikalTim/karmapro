// The AI conversation as the browser shows it: the server's chat state plus
// the `ai.stream` events that arrive between two state fetches. Everything
// here is pure, so the rules the window follows can be tested without a DOM.
import { escapeHtml, renderMarkdown } from "../../../lib/markdown";
import type { AIChatEntry, AIChatState, AIStreamEvent } from "./types";

/**
 * What to do with one stream event:
 *  - `stale`: the state already includes it (its seq is not newer);
 *  - `gap`: an earlier event was missed, so the state must be fetched first;
 *  - `refetch`: the round ended, so the state is fetched for the final transcript;
 *  - `applied`: the event changed the state (`state` is the new state).
 */
export type StreamStep =
  | { kind: "stale" }
  | { kind: "gap" }
  | { kind: "refetch" }
  | { kind: "applied"; state: AIChatState };

interface ToolPayload {
  label: string;
  output: string;
}

/** The `tool` event's text: the transcript's tool entry as JSON. */
function parseToolPayload(text: string): ToolPayload | null {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof value !== "object" || value === null) return null;
  const label = "label" in value ? value.label : undefined;
  const output = "output" in value ? value.output : undefined;
  if (typeof label !== "string" || typeof output !== "string") return null;
  return { label, output };
}

/** Applies an event's change, or returns null when the event asks for a fresh state. */
function applyKind(state: AIChatState, event: AIStreamEvent): AIChatState | null {
  switch (event.kind) {
    case "delta":
      return { ...state, streaming: state.streaming + event.text, thinking: false };
    case "thinking":
      return { ...state, thinking: true };
    case "tool": {
      const payload = parseToolPayload(event.text);
      if (!payload) return state;
      // The text streamed before the tools is dropped by the server once they
      // run, so it leaves the pane here too; no token arrives until the next round.
      const entry: AIChatEntry = { kind: "tool", text: payload.label, output: payload.output };
      return { ...state, transcript: [...state.transcript, entry], streaming: "", thinking: false };
    }
    case "status":
      return { ...state, status: event.text, statusLevel: event.level ?? "info" };
    case "error":
      return { ...state, status: event.text, statusLevel: "error" };
    case "turnFinished":
      return null;
    default:
      return state;
  }
}

/** Applies one `ai.stream` event to the state the server reported at `state.seq`. */
export function reduceStreamEvent(state: AIChatState, event: AIStreamEvent): StreamStep {
  if (event.seq <= state.seq) return { kind: "stale" };
  if (event.seq > state.seq + 1) return { kind: "gap" };
  const next = applyKind(state, event);
  if (next === null) return { kind: "refetch" };
  return { kind: "applied", state: { ...next, seq: event.seq } };
}

/**
 * The finished part of the transcript, as the response pane lays it out:
 * a dim marker line per prompt, the tool label and its indented output, and
 * each answer as markdown followed by a blank line, as the AppKit pane lays them out.
 */
export function transcriptHTML(entries: readonly AIChatEntry[]): string {
  let html = "";
  for (const entry of entries) {
    if (entry.kind === "turn") {
      html += `<span class="ai-turn">${escapeHtml(entry.text)}</span>\n`;
    } else if (entry.kind === "tool") {
      html +=
        `<span class="ai-tool">${escapeHtml(entry.text)}</span>\n` +
        `<span class="ai-tool-output">  ${escapeHtml(entry.output ?? "")}</span>\n\n`;
    } else {
      html += `${renderMarkdown(entry.text)}\n`;
    }
  }
  return html;
}

/** The answer being written, with the blinking-cursor block while a request runs. */
export function liveHTML(streaming: string, requestInFlight: boolean): string {
  const cursor = requestInFlight ? `<span class="ai-cursor">\u258d</span>` : "";
  return renderMarkdown(streaming) + cursor;
}

/** The Send button's title and tooltip: it becomes Stop while a request runs. */
export function sendButton(chat: Pick<AIChatState, "requestInFlight">): { title: string; tooltip: string } {
  return chat.requestInFlight
    ? { title: "Stop", tooltip: "Cancel the in-flight request (partial response is kept)" }
    : { title: "Send to AI", tooltip: "Send the prompt to the selected model" };
}

/** Continue works only for an interrupted task, and never while a request runs. */
export function continueEnabled(chat: AIChatState): boolean {
  return !chat.requestInFlight && chat.canContinue;
}

/** New Chat clears a conversation, and cannot do so while a request runs. */
export function newChatEnabled(chat: AIChatState): boolean {
  return !chat.requestInFlight && chat.canNewChat;
}
