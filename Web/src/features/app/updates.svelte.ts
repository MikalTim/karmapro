// The update state behind the Karma Pro menu. `update.changed` events keep it current
// (`startUpdateNotifications` subscribes to them).
import { api } from "../../lib/api";
import { showAlert } from "../../lib/ui/alert.svelte";
import type { MenuItem } from "../../lib/ui/contextMenu.svelte";
import { updateMenuModel, type UpdateStateDTO } from "./updateModel";

export const updateState = $state<{ value: UpdateStateDTO | null }>({ value: null });

export function setUpdateState(next: UpdateStateDTO): void {
  updateState.value = next;
}

/** A request that could not be made or answered is reported as the alert text of its error. */
async function showRequestFailure(error: unknown): Promise<void> {
  await showAlert({ message: error instanceof Error ? error.message : String(error), style: "warning" });
}

/** `POST /api/updates/check`. The menu item follows the `update.changed` events the check posts. */
export async function runUpdateCheck(): Promise<void> {
  try {
    await api("POST", "/api/updates/check");
  } catch (error) {
    await showRequestFailure(error);
  }
}

/** `PUT /api/updates/automatic`. Turning it on checks at once when the daily gate allows. */
export async function setAutomaticChecks(enabled: boolean): Promise<void> {
  try {
    setUpdateState(await api<UpdateStateDTO>("PUT", "/api/updates/automatic", { enabled }));
  } catch (error) {
    await showRequestFailure(error);
  }
}

/** The items of the Karma Pro update section, read when the menu opens. */
export function updateMenuItems(): MenuItem[] {
  return updateMenuModel(updateState.value, {
    check: () => void runUpdateCheck(),
    setAutomatic: (enabled) => void setAutomaticChecks(enabled),
    openPage: (url) => {
      window.open(url, "_blank", "noopener");
    },
  });
}
