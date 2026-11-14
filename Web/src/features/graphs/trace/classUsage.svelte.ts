// The class-usage window (`ClassUsageWindowController`). The search is a job
// with no progress. Unlike AppKit's synchronous load, the browser's request can
// remain pending, so its window opens before the answer and can cancel the job.
// One window is shared; a new search replaces the content.
import { api } from "../../../lib/api";
import type { DiagramGraphDTO } from "../flow";
import { type RunningJob, runJob } from "../../../lib/jobs";
import { showAlert } from "../../../lib/ui/alert.svelte";
import { asWindowContent, openWindow, setWindowTitle } from "../../../lib/ui/windows.svelte";
import type { ClassUsageDTO } from "./dto";
import ClassUsageWindow from "./ClassUsageWindow.svelte";

/** What the window shows. Mutated in place; the window component reads it. */
export const classUsage = $state<{
  heading: string;
  status: string;
  emptyMessage: string | null;
  graph: DiagramGraphDTO | null;
}>({ heading: "", status: "", emptyMessage: null, graph: null });

/** Bumped by every search, so an older search that finishes late is dropped. */
let generation = 0;
let running: RunningJob<ClassUsageDTO> | null = null;

/** Finds every `new className(` in the project and shows where it is instantiated. */
export function openClassUsageWindow(target: { className: string }): void {
  void search(target.className);
}

async function search(className: string): Promise<void> {
  stopRunning();
  const current = ++generation;
  classUsage.heading = `Where is “${className}” instantiated?`;
  classUsage.status = "";
  classUsage.emptyMessage = null;
  classUsage.graph = null;
  const id = openWindow({
    key: "ClassUsageWindow",
    title: `Instantiations of ${className}`,
    width: 900,
    height: 600,
    minWidth: 560,
    minHeight: 360,
    escCloses: true,
    component: asWindowContent(ClassUsageWindow),
    onClose: stopRunning,
  });
  setWindowTitle(id, `Instantiations of ${className}`);
  const job = runJob<ClassUsageDTO>(api<{ jobId: string }>("POST", "/api/class-usage", { className }));
  running = job;
  try {
    const outcome = await job.promise;
    if (current !== generation || outcome.status === "cancelled" || !outcome.result) return;
    const dto = outcome.result;
    classUsage.heading = dto.title;
    classUsage.status = dto.status;
    classUsage.emptyMessage = dto.emptyMessage ?? null;
    classUsage.graph = dto.graph ?? null;
    setWindowTitle(id, dto.windowTitle);
  } catch (error) {
    if (current !== generation) return;
    await showAlert({ message: error instanceof Error ? error.message : String(error), style: "warning" });
  } finally {
    if (current === generation) running = null;
  }
}

function stopRunning(): void {
  generation++;
  const job = running;
  running = null;
  if (job) job.cancel().catch(() => undefined);
}
