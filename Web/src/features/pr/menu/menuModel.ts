// The entries of the pull request status menu, built from the server's state. The order and titles are those
// of `PRMenuBarController.rebuild`.
import type { PRState } from "./prTypes";

export type PRMenuAction =
  | { kind: "enableMonitoring" }
  | { kind: "disableMonitoring" }
  | { kind: "checkNow" }
  | { kind: "setDepth"; value: string }
  | { kind: "setNotifyStyle"; value: string }
  | { kind: "manageRepositories" }
  | { kind: "accounts" }
  | { kind: "about" }
  | { kind: "quit" };

export type PRMenuItem = {
  kind: "item";
  title: string;
  action: PRMenuAction;
  checked: boolean;
  indented: boolean;
  tooltip?: string;
  /** The key letter of the key equivalent, when the item has one. */
  keyEquivalent?: string;
};

export type PRMenuEntry = { kind: "separator" } | { kind: "label"; title: string; indented: boolean } | PRMenuItem;

function command(title: string, action: PRMenuAction): PRMenuItem {
  return { kind: "item", title, action, checked: false, indented: false };
}

/** A disabled line of text (`disabledItem`). */
function label(title: string): PRMenuEntry {
  return { kind: "label", title, indented: false };
}

const separator: PRMenuEntry = { kind: "separator" };

/** The menu when monitoring is off: monitoring is only offered, nothing is polled. */
function offEntries(): PRMenuEntry[] {
  return [
    label("Pull request monitoring is off"),
    separator,
    command("Enable Monitoring\u2026", { kind: "enableMonitoring" }),
    command("Manage Repositories\u2026", { kind: "manageRepositories" }),
    command("Accounts\u2026", { kind: "accounts" }),
    separator,
    command("Quit Karma Pro", { kind: "quit" }),
  ];
}

/** The menu's entries for the given state, in display order. */
export function buildPRMenu(state: PRState): PRMenuEntry[] {
  if (!state.monitoringEnabled) return offEntries();

  const entries: PRMenuEntry[] = [];
  // The last poll's failure, as one line. The full text is in the repositories window, which is too narrow
  // for it here.
  if (state.pollError) entries.push(label(state.pollError), separator);

  entries.push(
    command("Check Now", { kind: "checkNow" }),
    command("Disable Monitoring", { kind: "disableMonitoring" }),
    separator,
    label("Scan depth:"),
  );
  for (const choice of state.depthChoices) {
    entries.push({
      kind: "item",
      title: choice.title,
      action: { kind: "setDepth", value: choice.value },
      checked: choice.selected,
      indented: true,
      tooltip: choice.explanation,
    });
  }

  entries.push(label("Alert me about new PRs:"));
  for (const choice of state.notifyChoices) {
    entries.push({
      kind: "item",
      title: choice.title,
      action: { kind: "setNotifyStyle", value: choice.value },
      checked: choice.selected,
      indented: true,
    });
  }

  entries.push(
    separator,
    command("Manage Repositories\u2026", { kind: "manageRepositories" }),
    command("Accounts\u2026", { kind: "accounts" }),
    command("About Pull Request Reviews", { kind: "about" }),
    separator,
    { ...command("Quit Karma Pro", { kind: "quit" }), keyEquivalent: "q" },
  );
  return entries;
}

/** The status icon's tooltip; the faded icon says the same in words. */
export function statusTooltip(monitoring: boolean): string {
  return monitoring ? "Karma Pro pull requests monitoring" : "Karma Pro pull requests monitoring (off)";
}

/** The status icon's accessible name, so a dimmed icon is not the only sign that monitoring is paused. */
export function statusAccessibilityLabel(monitoring: boolean): string {
  return monitoring ? "Pull request monitoring" : "Pull request monitoring, off";
}
