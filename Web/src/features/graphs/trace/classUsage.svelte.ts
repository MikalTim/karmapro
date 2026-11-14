// The class-usage window (`ClassUsageWindowController`). The search is a job
// with no progress, and AppKit showed the window only once the search had
// finished, so the window opens with its result. One window is shared; a new
// search replaces the content, and it is focused when already open.
import { api } from "../../../lib/api";
import type { DiagramGraphDTO } from "../flow";
import { runJob } from "../../../lib/jobs";
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

/** Finds every `new className(` in the project and shows where it is instantiated. */
export function openClassUsageWindow(target: { className: string }): void {
  void search(target.className);
}

async function search(className: string): Promise<void> {
  const current = ++generation;
  let dto: ClassUsageDTO;
  try {
    const outcome = await runJob<ClassUsageDTO>(api<{ jobId: string }>("POST", "/api/class-usage", { className })).promise;
    if (current !== generation || outcome.status === "cancelled" || !outcome.result) return;
    dto = outcome.result;
  } catch (error) {
    if (current !== generation) return;
    await showAlert({ message: error instanceof Error ? error.message : String(error), style: "warning" });
    return;
  }
  classUsage.heading = dto.title;
  classUsage.status = dto.status;
  classUsage.emptyMessage = dto.emptyMessage ?? null;
  classUsage.graph = dto.graph ?? null;
  const id = openWindow({
    key: "ClassUsageWindow",
    title: dto.windowTitle,
    width: 900,
    height: 600,
    minWidth: 560,
    minHeight: 360,
    escCloses: true,
    component: asWindowContent(ClassUsageWindow),
  });
  setWindowTitle(id, dto.windowTitle);
}
