import { describe, expect, it } from "vitest";
import { renderMarkdown } from "../../../lib/markdown";
import {
  continueEnabled,
  liveHTML,
  newChatEnabled,
  reduceStreamEvent,
  sendButton,
  transcriptHTML,
} from "./chatModel";
import type { AIChatState, AIStreamEvent } from "./types";

function chat(overrides: Partial<AIChatState> = {}): AIChatState {
  return {
    transcript: [],
    streaming: "",
    thinking: false,
    requestInFlight: false,
    canContinue: false,
    canNewChat: false,
    status: "",
    statusLevel: "info",
    sendTitle: "Send to AI",
    seq: 5,
    ...overrides,
  };
}

function event(seq: number, kind: string, text = "", level?: string): AIStreamEvent {
  return { seq, kind, text, level };
}

describe("reduceStreamEvent", () => {
  it("ignores an event the state already includes", () => {
    expect(reduceStreamEvent(chat(), event(5, "delta", "x"))).toEqual({ kind: "stale" });
    expect(reduceStreamEvent(chat(), event(3, "delta", "x"))).toEqual({ kind: "stale" });
  });

  it("asks for the state again when an event was missed", () => {
    expect(reduceStreamEvent(chat(), event(7, "delta", "x"))).toEqual({ kind: "gap" });
  });

  it("appends streamed text and ends the thinking indicator", () => {
    const state = chat({ streaming: "Hel", thinking: true, requestInFlight: true });
    const step = reduceStreamEvent(state, event(6, "delta", "lo"));
    expect(step).toEqual({
      kind: "applied",
      state: expect.objectContaining({ streaming: "Hello", thinking: false, seq: 6 }),
    });
  });

  it("shows the thinking indicator without any answer text", () => {
    const step = reduceStreamEvent(chat({ requestInFlight: true }), event(6, "thinking"));
    expect(step.kind === "applied" && step.state.thinking).toBe(true);
    expect(step.kind === "applied" && step.state.streaming).toBe("");
  });

  it("adds a tool entry from the event's JSON and drops the text streamed before the tools", () => {
    const state = chat({ streaming: "Let me look", requestInFlight: true });
    const payload = JSON.stringify({ label: "read_file vuln.c", output: "10 lines" });
    const step = reduceStreamEvent(state, event(6, "tool", payload));
    expect(step.kind === "applied" && step.state.transcript).toEqual([
      { kind: "tool", text: "read_file vuln.c", output: "10 lines" },
    ]);
    expect(step.kind === "applied" && step.state.streaming).toBe("");
  });

  it("keeps the state when a tool event's text is not the expected JSON", () => {
    const step = reduceStreamEvent(chat(), event(6, "tool", "not json"));
    expect(step).toEqual({ kind: "applied", state: expect.objectContaining({ transcript: [], seq: 6 }) });
  });

  it("sets the status line with its level", () => {
    const step = reduceStreamEvent(chat(), event(6, "status", "Receiving response…", "info"));
    expect(step.kind === "applied" && step.state.status).toBe("Receiving response…");
    expect(step.kind === "applied" && step.state.statusLevel).toBe("info");
  });

  it("shows an error event in the error colour", () => {
    const step = reduceStreamEvent(chat(), event(6, "error", "Request failed."));
    expect(step.kind === "applied" && step.state.statusLevel).toBe("error");
  });

  it("asks for the final state when a round ends", () => {
    expect(reduceStreamEvent(chat(), event(6, "turnFinished"))).toEqual({ kind: "refetch" });
  });
});

describe("transcriptHTML", () => {
  it("writes each entry in order: prompt markers, tool lines and answers", () => {
    const html = transcriptHTML([
      { kind: "turn", text: "> audit <auth>" },
      { kind: "tool", text: "list_files src", output: "3 files" },
      { kind: "answer", text: "**Done**" },
    ]);
    expect(html).toBe(
      '<span class="ai-turn">&gt; audit &lt;auth&gt;</span>\n' +
        '<span class="ai-tool">list_files src</span>\n' +
        '<span class="ai-tool-output">  3 files</span>\n\n' +
        renderMarkdown("**Done**") +
        "\n",
    );
  });

  it("escapes tool output so that it cannot inject markup", () => {
    const html = transcriptHTML([{ kind: "tool", text: "run_command", output: "<img src=x>" }]);
    expect(html).toContain("  &lt;img src=x&gt;");
    expect(html).not.toContain("<img");
  });

  it("renders an empty transcript as nothing", () => {
    expect(transcriptHTML([])).toBe("");
  });
});

describe("liveHTML", () => {
  it("shows the blinking cursor only while a request runs", () => {
    expect(liveHTML("Hi", true)).toBe(renderMarkdown("Hi") + '<span class="ai-cursor">\u258d</span>');
    expect(liveHTML("Hi", false)).toBe(renderMarkdown("Hi"));
  });
});

describe("button rules", () => {
  it("titles Send as Stop while a request runs", () => {
    expect(sendButton({ requestInFlight: false })).toEqual({
      title: "Send to AI",
      tooltip: "Send the prompt to the selected model",
    });
    expect(sendButton({ requestInFlight: true }).title).toBe("Stop");
  });

  it("enables Continue only for an interrupted task that is not running", () => {
    expect(continueEnabled(chat({ canContinue: true }))).toBe(true);
    expect(continueEnabled(chat({ canContinue: true, requestInFlight: true }))).toBe(false);
    expect(continueEnabled(chat({ canContinue: false }))).toBe(false);
  });

  it("enables New Chat only when there is a conversation and nothing runs", () => {
    expect(newChatEnabled(chat({ canNewChat: true }))).toBe(true);
    expect(newChatEnabled(chat({ canNewChat: true, requestInFlight: true }))).toBe(false);
    expect(newChatEnabled(chat({ canNewChat: false }))).toBe(false);
  });
});
