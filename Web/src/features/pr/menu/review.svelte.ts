// The pull request state the whole page shares. The menu, the banner, the changes and report windows, and the
// main window (its title and tree) read it. Every `pr.changed` replaces it, so it always matches the server.
import { api } from "../../../lib/api";
import { on } from "../../../lib/events";
import { closeWindow } from "../../../lib/ui/windows.svelte";
import type { RunningJob } from "../../../lib/jobs";
import type { PRChanges, PRItem, PRReport, PRState } from "./prTypes";

export const reviewState = $state<{ value: PRState | null }>({ value: null });

export function setPRState(state: PRState): void {
  reviewState.value = state;
}

export async function refreshPRState(): Promise<PRState> {
  const state = await api<PRState>("GET", "/api/pr");
  setPRState(state);
  return state;
}

on<PRState>("pr.changed", setPRState);
// `pr.review` says a review opened or closed; the full state follows in `pr.changed`, but the banner must not
// depend on the order the two events arrive in.
on("pr.review", () => {
  refreshPRState().catch((error: unknown) => console.error("Could not read the pull request state:", error));
});
refreshPRState().catch((error: unknown) => console.error("Could not read the pull request state:", error));

/** The changes window's content. It is one window, so showing the changes again replaces this. */
export const changesView = $state<{ changes: PRChanges | null; index: number }>({ changes: null, index: 0 });

export interface ReportStatus {
  text: string;
  error: boolean;
}

/** The report window's content. `status` null shows the report's own status text. */
export const reportView = $state<{ report: PRReport | null; status: ReportStatus | null }>({
  report: null,
  status: null,
});

/**
 * The "Preparing review" window's state: the pull request, the job's progress, and the window to close when the
 * job ends. Cancel, Escape and the title-bar close button all mean the same thing, as in `PRProgressPanel`.
 */
export class PreparingReview {
  readonly item: PRItem;
  /** The bar's position from 0 to 1. Starts at 2 %, as `PRProgressPanelController` does. */
  fraction = $state(0.02);
  stage = $state("Starting\u2026");

  #job: RunningJob<PRState> | null = null;
  #windowId: number | null = null;
  #finished = false;
  #cancelled = false;

  constructor(item: PRItem) {
    this.item = item;
  }

  /** Whether the user asked to stop. A late failure after a cancel is not reported. */
  get wasCancelled(): boolean {
    return this.#cancelled;
  }

  update(fraction: number, stage: string): void {
    this.fraction = Math.max(0, Math.min(1, fraction));
    this.stage = stage;
  }

  attach(job: RunningJob<PRState>, windowId: number): void {
    this.#job = job;
    this.#windowId = windowId;
  }

  cancel(): void {
    if (this.#finished) return;
    this.#finished = true;
    this.#cancelled = true;
    // A failed cancel leaves the job to finish by itself; its completion path has nothing left to report.
    this.#job?.cancel().catch(() => undefined);
    this.#closeWindow();
  }

  /** The job completed or failed: the window goes away. */
  finish(): void {
    if (this.#finished) return;
    this.#finished = true;
    this.#closeWindow();
  }

  #closeWindow(): void {
    const id = this.#windowId;
    this.#windowId = null;
    if (id !== null) void closeWindow(id);
  }
}
