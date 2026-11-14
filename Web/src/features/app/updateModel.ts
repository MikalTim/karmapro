// The update menu and the outcome alerts of `UpdateMenuTarget`, as plain data. The server
// computes every title and message (`UpdateService`); this file only arranges them.
import type { MenuItem } from "../../lib/ui/contextMenu.svelte";

/** `UpdateService.UpdateOutcomeDTO`: what a finished check presents. */
export interface UpdateOutcomeDTO {
  kind: "upToDate" | "updateAvailable" | "failed";
  title: string;
  message: string;
  version: string | null;
  publishedAt: string | null;
  downloadURL: string;
}

/** `UpdateService.UpdateStateDTO`: what the menu and the `update.changed` event carry. */
export interface UpdateStateDTO {
  currentVersion: string;
  automaticChecks: boolean;
  lastCheckedAt: string | null;
  checkRunning: boolean;
  checkMenuTitle: string;
  knownNewerVersion: string | null;
  availableMenuTitle: string | null;
  downloadURL: string;
  lastOutcome: UpdateOutcomeDTO | null;
}

export interface UpdateMenuActions {
  check: () => void;
  setAutomatic: (enabled: boolean) => void;
  openPage: (url: string) => void;
}

/**
 * The Karma Pro menu section for updates: check, separator, automatic, availability, separator.
 * The availability row exists only while a newer release is known, so the section never leaves
 * a dead entry or two stacked separators.
 */
export function updateMenuModel(state: UpdateStateDTO | null, actions: UpdateMenuActions): MenuItem[] {
  const automatic = state?.automaticChecks ?? false;
  const items: MenuItem[] = [
    { title: state?.checkMenuTitle ?? "Check for Updates…", disabled: state?.checkRunning ?? false, action: actions.check },
    { separator: true },
    { title: "Check for Updates Automatically", checked: automatic, action: () => actions.setAutomatic(!automatic) },
  ];
  if (state?.availableMenuTitle) {
    // Always the download page, whatever a stored link says (`openKnownUpdate`).
    const url = state.downloadURL;
    items.push({ title: state.availableMenuTitle, action: () => actions.openPage(url) });
  }
  items.push({ separator: true });
  return items;
}

/**
 * Identifies the outcome a state carries. A new check always moves `lastCheckedAt`, so a repeated
 * failure or a repeated "up to date" still counts as new and is presented again.
 */
export function outcomeKey(state: UpdateStateDTO): string {
  const outcome = state.lastOutcome;
  return outcome ? `${state.lastCheckedAt ?? ""}|${outcome.kind}|${outcome.title}` : "";
}

export type OutcomePresentation =
  | { via: "notification" }
  | { via: "alert"; buttons: string[]; download: boolean };

/**
 * How a finished check reaches the user (`UpdateMenuTarget.apply`). An available update is an
 * alert while the page has focus, and a notification otherwise. Every other outcome is an alert.
 */
export function outcomePresentation(outcome: UpdateOutcomeDTO, focused: boolean): OutcomePresentation {
  if (outcome.kind === "updateAvailable") {
    return focused
      ? { via: "alert", buttons: ["Download", "Later"], download: true }
      : { via: "notification" };
  }
  return { via: "alert", buttons: ["OK"], download: false };
}
