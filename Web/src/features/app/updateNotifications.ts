// Tells the user when a check finishes (`UpdateMenuTarget.apply`): an alert while the page has
// focus, a notification otherwise. An outcome the user has already been told about is never shown again.
import { api } from "../../lib/api";
import { on } from "../../lib/events";
import { showAlert } from "../../lib/ui/alert.svelte";
import {
  outcomeKey,
  outcomePresentation,
  type UpdateOutcomeDTO,
  type UpdateStateDTO,
} from "./updateModel";
import { setUpdateState, updateState } from "./updates.svelte";

let started = false;

/** Subscribes to `update.changed` and seeds the menu state. Call once at launch. */
export function startUpdateNotifications(): void {
  if (started) return;
  started = true;

  // Outcomes present before the first state load belong to earlier sessions, so they are
  // remembered as shown rather than presented.
  let baselined = false;
  let applied: string | null = null;

  on<UpdateStateDTO>("update.changed", (next) => {
    setUpdateState(next);
    if (!baselined) return;
    const key = outcomeKey(next);
    if (next.checkRunning || next.lastOutcome === null || key === applied) return;
    applied = key;
    present(next.lastOutcome, next.downloadURL);
  });

  api<UpdateStateDTO>("GET", "/api/updates").then(
    (initial) => {
      if (updateState.value === null) setUpdateState(initial);
      baselined = true;
      applied = outcomeKey(initial);
    },
    () => {
      // Without an initial state nothing is known to be shown already; the next outcome is presented.
      baselined = true;
    },
  );
}

function present(outcome: UpdateOutcomeDTO, downloadURL: string): void {
  const plan = outcomePresentation(outcome, document.hasFocus());
  if (plan.via === "alert") {
    void showAlert({ message: outcome.title, informative: outcome.message, buttons: plan.buttons }).then((button) => {
      if (plan.download && button === 0) window.open(downloadURL, "_blank", "noopener");
    });
    return;
  }
  // Only when permission is already granted: the update check never asks for it.
  if (typeof Notification === "undefined" || Notification.permission !== "granted") return;
  const notice = new Notification(outcome.title, { body: outcome.message, tag: "karma.update.available" });
  notice.onclick = () => {
    window.open(downloadURL, "_blank", "noopener");
    notice.close();
  };
}
