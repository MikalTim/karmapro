// The variable-flow window (`VariableFlowWindowController` and the trace
// requests of `MainWindowController.showVariableFlow`). One window is shared, as
// in AppKit: a new request replaces the trace in it, and closing the window
// while a search runs cancels the search.
import { api } from "../../../lib/api";
import { type RunningJob, runJob } from "../../../lib/jobs";
import { asWindowContent, openWindow, setWindowTitle } from "../../../lib/ui/windows.svelte";
import type { VariableFlowDTO } from "./dto";
import { indexedProgressText, progressFraction } from "./progress";
import VariableFlowWindow from "./VariableFlowWindow.svelte";

export interface VariableFlowProgress {
  /** 0...1 for the bar. */
  fraction: number;
  label: string;
}

/** What the window shows. Mutated in place; the window component reads it. */
export const variableFlow = $state<{
  heading: string;
  caption: string;
  progress: VariableFlowProgress | null;
  result: VariableFlowDTO | null;
}>({ heading: "", caption: "", progress: null, result: null });

export interface VariableFlowRequest {
  path: string;
  location: number;
  variable: string;
}

let windowId: number | null = null;
let running: RunningJob<VariableFlowDTO> | null = null;
/** Bumped by every request and cancel, so an answer to an older request is dropped. */
let generation = 0;

/** Traces `variable` (used at UTF-16 offset `location` of `path`) across the project in the shared window. */
export function openVariableFlowWindow(request: VariableFlowRequest): void {
  void trace(request);
}

async function trace(request: VariableFlowRequest): Promise<void> {
  stopRunning();
  const current = ++generation;
  const id = openWindow({
    key: "VariableFlowWindow",
    title: "Variable Flow",
    width: 1000,
    height: 720,
    minWidth: 640,
    minHeight: 420,
    escCloses: true,
    component: asWindowContent(VariableFlowWindow),
    onClose: cancelOnClose,
  });
  windowId = id;
  setWindowTitle(id, `Variable Flow — ${request.variable}`);
  variableFlow.heading = `Flow of “${request.variable}”`;
  variableFlow.caption = `Searching the project for “${request.variable}”…`;
  variableFlow.progress = { fraction: 0, label: "Enumerating source files…" };
  variableFlow.result = null;

  const startedAt = Date.now();
  const job = runJob<VariableFlowDTO>(api<{ jobId: string }>("POST", "/api/variable-flow", request), (progress) => {
    if (current !== generation || !variableFlow.progress) return;
    const fraction = progressFraction(progress.done, progress.total);
    variableFlow.progress = {
      fraction: fraction ?? variableFlow.progress.fraction,
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
    variableFlow.progress = null;
    variableFlow.caption = error instanceof Error ? error.message : String(error);
  }
}

function display(result: VariableFlowDTO): void {
  variableFlow.progress = null;
  variableFlow.heading = result.title;
  variableFlow.caption = result.caption;
  variableFlow.result = result;
  if (windowId !== null) setWindowTitle(windowId, result.windowTitle);
}

function stopRunning(): void {
  generation++;
  const job = running;
  running = null;
  if (job) job.cancel().catch(() => undefined);
}

/** `windowWillClose`: only a running search is cancelled. */
function cancelOnClose(): void {
  if (running) stopRunning();
}
