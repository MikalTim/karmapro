// The AI window's status line: its text and the level that picks the colour
// (`AIWindowController.setStatus`, `ProviderManagerController.setStatus`).

export interface StatusLine {
  text: string;
  level: string;
}

export const idleStatus: StatusLine = { text: "", level: "info" };

/** The CSS colour for a status level. Unknown levels fall back to the secondary label colour. */
export function statusColor(level: string): string {
  switch (level) {
    case "error":
      return "var(--system-red)";
    case "warning":
      return "var(--system-orange)";
    case "success":
      return "var(--system-green)";
    default:
      return "var(--secondary-label)";
  }
}
