// Decisions behind the pull request alerts, and the list of in-page toasts. Pure, so the rules can be tested
// without a browser; `notifications.ts` and `toasts.svelte.ts` apply them.
import type { PRNotification, PRState } from "./prTypes";

/** The `notifyStyle` raw value that turns alerts off (`PRKind.NotifyStyle.off`). */
const NOTIFY_OFF = "off";

/** The alert style the user picked: the choice the server marks as selected. */
export function notifyStyleOf(state: PRState): string {
  return state.notifyChoices.find((choice) => choice.selected)?.value ?? NOTIFY_OFF;
}

/**
 * Whether to ask the browser for notification permission now. AppKit asks once the user has turned alerts on;
 * here that is a state that wants alerts while the browser has not answered yet.
 */
export function needsPermissionRequest(style: string, permission: NotificationPermission | "unsupported"): boolean {
  return style !== NOTIFY_OFF && permission === "default";
}

/** A toast's identity: the same pull request is one toast even when it is announced twice. */
export function toastKey(item: { repoID: string; prID: number }): string {
  return JSON.stringify([item.repoID, item.prID]);
}

export interface PRToast extends PRNotification {
  key: string;
}

/** The toast list with `item` added at the end; an announcement of the same pull request replaces the old toast. */
export function withToast(toasts: PRToast[], item: PRNotification): PRToast[] {
  const key = toastKey(item);
  return [...toasts.filter((toast) => toast.key !== key), { ...item, key }];
}

export function withoutToast(toasts: PRToast[], key: string): PRToast[] {
  return toasts.filter((toast) => toast.key !== key);
}
