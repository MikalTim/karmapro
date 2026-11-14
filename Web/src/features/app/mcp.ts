// The text of the MCP Settings window (`MCPSettingsWindowController.refresh`). The state
// comes from `GET /api/mcp` and `mcp.changed` as `MCPStateDTO`.

export interface MCPStateDTO {
  running: boolean;
  url: string;
  clientConfig: string;
  port: number;
  allowAI: boolean;
  autoStart: boolean;
  scanCount: number;
  lastError: string;
  /** ISO 8601 start time of the running listener (`startedAt` in MCPSettingsWindowController). Absent until the server sends it. */
  startedAt?: string | null;
}

/** The status line: where the service listens while it runs, else "Stopped". */
export function statusText(state: Pick<MCPStateDTO, "running" | "port">): string {
  return state.running ? `Running on 127.0.0.1:${state.port}` : "Stopped";
}

export function serviceButtonTitle(running: boolean): string {
  return running ? "Stop Service" : "Start Service";
}

export function scanCountText(count: number): string {
  return `${count} scan${count === 1 ? "" : "s"} served this session`;
}

/**
 * The statistics line (`MCPSettingsWindowController.refresh`): the scan count, then the uptime in whole
 * minutes once the listener has a start time. A start time that is missing or unreadable adds nothing.
 */
export function statsText(state: Pick<MCPStateDTO, "scanCount" | "startedAt">, now: Date): string {
  const base = scanCountText(state.scanCount);
  if (!state.startedAt) return base;
  const started = Date.parse(state.startedAt);
  if (Number.isNaN(started)) return base;
  const minutes = Math.trunc((now.getTime() - started) / 60000);
  return `${base} · up ${minutes} min`;
}

export const ELLIPSIS = "…";

/**
 * `NSLineBreakMode.byTruncatingMiddle` on one line: when `text` is wider than `available` px, the middle gives way to
 * an ellipsis and as many characters as fit stay at both ends (the head keeps the extra one when the count is odd).
 * `measure` returns the width in px of a string in the field's font.
 */
export function truncateMiddle(text: string, available: number, measure: (text: string) => number): string {
  if (measure(text) <= available) return text;
  const characters = Array.from(text);
  const joined = (kept: number): string => {
    const head = Math.ceil(kept / 2);
    return characters.slice(0, head).join("") + ELLIPSIS + characters.slice(characters.length - (kept - head)).join("");
  };
  // The widest string that fits: the width grows with every kept character, so a binary search finds it.
  let low = 0;
  let high = characters.length - 1;
  while (low < high) {
    const middle = Math.ceil((low + high) / 2);
    if (measure(joined(middle)) <= available) low = middle;
    else high = middle - 1;
  }
  return joined(low);
}
