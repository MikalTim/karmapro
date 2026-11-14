// The pull request review flows: starting a review from a notice, the scan question, the changes and report
// windows, Show All Files, Close Review and Ignore. Each function is the AppKit method named in its comment.
import { api } from "../../../lib/api";
import { runJob } from "../../../lib/jobs";
import { showAlert } from "../../../lib/ui/alert.svelte";
import { WINDOW_TITLE_BAR, asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import { showFileInMainWindow } from "../../main/navigation";
import { openPRScanWindow } from "../../scan";
import { errorMessage, showFailure } from "./failures";
import { PreparingReview, changesView, refreshPRState, reportView, setPRState } from "./review.svelte";
import type { PRChanges, PRReport, PRScanPrompt, PRState } from "./prTypes";
import PRDiffWindow from "./PRDiffWindow.svelte";
import PRProgressSheet from "./PRProgressSheet.svelte";
import PRReportWindow from "./PRReportWindow.svelte";

/**
 * `PRReviewCoordinator.startReview`: prepares the checkout as a job, shows the "Preparing review" window until
 * it ends, and opens the review when it completes.
 */
export async function reviewPullRequest(repoID: string, prID: number): Promise<void> {
  let state: PRState;
  try {
    state = await refreshPRState();
  } catch (error) {
    await showFailure(error);
    return;
  }
  if (!state.gitAvailable) {
    await showAlert({ message: "Git is not available", informative: state.gitUnavailableMessage, style: "warning" });
    return;
  }
  const item = state.items.find((candidate) => candidate.repoID === repoID && candidate.prID === prID);
  if (!item) {
    await showAlert({
      message: "Could not prepare the review",
      informative: "That pull request is no longer in the watch list.",
      style: "warning",
    });
    return;
  }

  const progress = new PreparingReview(item);
  const windowId = openWindow({
    title: "Preparing review",
    width: 440,
    height: 163,
    minWidth: 440,
    minHeight: 163,
    escCloses: true,
    component: asWindowContent(PRProgressSheet),
    props: { progress },
    onClose: () => progress.cancel(),
  });
  const job = runJob<PRState>(api<{ jobId: string }>("POST", "/api/pr/review", { repoID, prID }), (event) =>
    progress.update(event.total > 0 ? event.done / event.total : 0, event.stage),
  );
  progress.attach(job, windowId);

  void job.promise.then(
    (outcome) => {
      progress.finish();
      if (outcome.status === "completed" && outcome.result) setPRState(outcome.result);
    },
    async (error: unknown) => {
      const cancelled = progress.wasCancelled;
      progress.finish();
      if (cancelled) return;
      await showAlert({ message: "Could not prepare the review", informative: errorMessage(error), style: "warning" });
    },
  );
}

/**
 * `runPullRequestScan`: asks how far the AI pass should reach, opens the scan window, then starts the scan.
 * "Regular scan only" and an unrecognised answer both run the scan without AI.
 */
export async function runPullRequestScan(): Promise<void> {
  try {
    const prompt = await api<PRScanPrompt>("GET", "/api/pr/review/scan-prompt");
    const pressed = await showAlert({
      message: prompt.title,
      informative: prompt.message,
      style: "informational",
      buttons: prompt.choices.map((choice) => choice.title),
    });
    const scope = prompt.choices[pressed]?.value ?? "none";
    // The scan window follows a scan the server has already started, so a refused start leaves no empty window.
    await api<{ jobId: string }>("POST", "/api/pr/review/scan", { scope });
    openPRScanWindow();
  } catch (error) {
    await showFailure(error);
  }
}

/** `showPullRequestChanges`: one changes window for the review; its first file is opened in the main window. */
export async function showPullRequestChanges(): Promise<void> {
  try {
    const changes = await api<PRChanges>("GET", "/api/pr/review/changes");
    changesView.changes = changes;
    changesView.index = 0;
    openWindow({
      key: "PRDiffWindow",
      title: changes.windowTitle,
      width: 900,
      height: 620,
      // AppKit's `minSize` is the frame's, title bar included; the window's minimum is for its content.
      minWidth: 560,
      minHeight: 320 - WINDOW_TITLE_BAR,
      escCloses: true,
      component: asWindowContent(PRDiffWindow),
    });
    const first = changes.files[0];
    if (first) showFileInMainWindow(first.absolutePath);
  } catch (error) {
    await showFailure(error);
  }
}

/** `showPullRequestReport`: the Markdown report, in the one report window. */
export async function showPullRequestReport(): Promise<void> {
  try {
    const report = await api<PRReport>("GET", "/api/pr/review/report");
    reportView.report = report;
    reportView.status = null;
    openWindow({
      key: "PRReportWindow",
      title: report.windowTitle,
      width: 760,
      height: 620,
      escCloses: true,
      component: asWindowContent(PRReportWindow),
    });
  } catch (error) {
    await showFailure(error);
  }
}

/** `leavePullRequestReview(removeCheckout: true)`: "Close Review" leaves at once, with no question. */
export async function leavePullRequestReview(): Promise<void> {
  try {
    await api("POST", "/api/pr/review/leave", { removeCheckout: true });
    await refreshPRState();
  } catch (error) {
    await showFailure(error);
  }
}

/** "Show All Files": lifts the pruning of the tree; the button then disappears. */
export async function showAllPullRequestFiles(): Promise<void> {
  try {
    setPRState(await api<PRState>("PUT", "/api/pr/review/show-all", { on: true }));
  } catch (error) {
    await showFailure(error);
  }
}

/** The Ignore action of a notice: drops the pull request from the watch list and from future alerts. */
export async function ignorePullRequest(repoID: string, prID: number): Promise<void> {
  try {
    await api("POST", "/api/pr/items/dismiss", { repoID, prID });
  } catch (error) {
    await showFailure(error);
  }
}
