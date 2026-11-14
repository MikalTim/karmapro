// The in-page notices for new pull requests, shown by `PRToasts.svelte`. A toast stays until it is acted on or
// dismissed, as a macOS notification stays in Notification Center.
import { withToast, withoutToast, type PRToast } from "./notifyPolicy";
import type { PRNotification } from "./prTypes";

export const toastList = $state<{ list: PRToast[] }>({ list: [] });

export function pushToast(item: PRNotification): void {
  toastList.list = withToast(toastList.list, item);
}

export function dismissToast(key: string): void {
  toastList.list = withoutToast(toastList.list, key);
}
