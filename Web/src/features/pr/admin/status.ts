// The status line of the PR admin windows, and how a failed request is shown.

/** `error` is red, `warning` orange and `info` the secondary label colour, as the AppKit status lines are. */
export type StatusTone = "info" | "warning" | "error";

export interface StatusLine {
  text: string;
  tone: StatusTone;
}

export function statusLine(text: string, tone: StatusTone = "info"): StatusLine {
  return { text, tone };
}

/** A server result: a failed one (`success` false) is shown in red. */
export function resultLine(result: { text: string; success: boolean }): StatusLine {
  return statusLine(result.text, result.success ? "info" : "error");
}

/** The tone named by the server ("error", "warning", "info"); anything else reads as information. */
export function toneNamed(name: string | null | undefined): StatusTone {
  if (name === "error" || name === "warning") return name;
  return "info";
}

export function statusColour(tone: StatusTone): string {
  switch (tone) {
    case "error":
      return "var(--system-red)";
    case "warning":
      return "var(--system-orange)";
    case "info":
      return "var(--secondary-label)";
  }
}

/**
 * How a failed request is shown. The server joins an alert's title and detail with a blank line, and the
 * AppKit dialogs present those as an alert; a plain message goes to the status line.
 */
export type Failure = { kind: "alert"; title: string; detail: string } | { kind: "status"; text: string };

export function classifyFailure(message: string): Failure {
  const split = message.indexOf("\n\n");
  if (split < 0) return { kind: "status", text: message };
  return { kind: "alert", title: message.slice(0, split), detail: message.slice(split + 2) };
}

export function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
