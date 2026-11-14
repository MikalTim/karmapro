// The reachability window (`ReachabilityWindowController` and the requests of
// `MainWindowController.showReachability`). One window is shared. While the
// project is indexed it shows a bar; once the call graph is built it shows a
// spinner until the walk finishes. Closing the window while the work runs
// cancels it.
import type { DiagramGraphDTO } from "../flow";
import { api } from "../../../lib/api";
import { type RunningJob, runJob } from "../../../lib/jobs";
import { asWindowContent, openWindow, setWindowTitle } from "../../../lib/ui/windows.svelte";
import type { ReachabilityDTO } from "./dto";
import { indexedProgressText, progressFraction } from "./progress";
import ReachabilityWindow from "./ReachabilityWindow.svelte";

/** What the window shows while the work runs. `null` once the result is shown. */
export type ReachabilityBusy =
  | { kind: "indexing"; fraction: number; label: string }
  | { kind: "analysing" };

export const reachability = $state<{
  heading: string;
  caption: string;
  busy: ReachabilityBusy | null;
  graph: DiagramGraphDTO | null;
}>({ heading: "", caption: "", busy: null, graph: null });

export interface ReachabilityRequest {
  path: string;
  functionName: string;
}

let windowId: number | null = null;
let running: RunningJob<ReachabilityDTO> | null = null;
let generation = 0;

/** Shows the project-wide reachability of `functionName`, defined in `path`, in the shared window. */
export function openReachabilityWindow(request: ReachabilityRequest): void {
  void trace(request);
}

async function trace(request: ReachabilityRequest): Promise<void> {
  stopRunning();
  const current = ++generation;
  const id = openWindow({
    key: "ReachabilityWindow",
    title: "Reachability",
    width: 1000,
    height: 720,
    minWidth: 640,
    minHeight: 420,
    escCloses: true,
    component: asWindowContent(ReachabilityWindow),
    onClose: cancelOnClose,
  });
  windowId = id;
  setWindowTitle(id, `Reachability — ${request.functionName}`);
  reachability.heading = `Reachability of “${request.functionName}”`;
  reachability.caption = "Building the project call graph…";
  reachability.busy = { kind: "indexing", fraction: 0, label: "Enumerating source files…" };
  reachability.graph = null;

  const startedAt = Date.now();
  const body = { path: request.path, function: request.functionName };
  const job = runJob<ReachabilityDTO>(api<{ jobId: string }>("POST", "/api/reachability", body), (progress) => {
    const busy = reachability.busy;
    if (current !== generation || busy === null || busy.kind === "analysing") return;
    if (progress.total > 0 && progress.done >= progress.total) {
      // The graph is built; the walk itself has no unit of work, so it spins.
      reachability.caption = "Analysing the project call graph…";
      reachability.busy = { kind: "analysing" };
      return;
    }
    const fraction = progressFraction(progress.done, progress.total);
    reachability.busy = {
      kind: "indexing",
      fraction: fraction ?? busy.fraction,
      label: indexedProgressText(progress.done, progress.total, (Date.now() - startedAt) / 1000),
    };
  });
  running = job;
  try {
    const outcome = await job.promise;
    if (current !== generation) return;
    running = null;
    if (outcome.status === "cancelled" || !outcome.result) return;
    display(outcome.result);
  } catch (error) {
    if (current !== generation) return;
    running = null;
    reachability.busy = null;
    reachability.caption = error instanceof Error ? error.message : String(error);
  }
}

function display(result: ReachabilityDTO): void {
  reachability.busy = null;
  reachability.heading = result.title;
  reachability.caption = result.caption;
  reachability.graph = result.graph ?? null;
  if (windowId !== null) setWindowTitle(windowId, result.windowTitle);
}

function stopRunning(): void {
  generation++;
  const job = running;
  running = null;
  if (job) job.cancel().catch(() => undefined);
}

/** `windowWillClose`: only a running walk is cancelled. */
function cancelOnClose(): void {
  if (running) stopRunning();
}
