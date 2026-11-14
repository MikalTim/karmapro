// The complexity-distribution window (`ComplexityScatterWindowController`). One
// window is shared: the file chart (`load(fileURL:)`) answers at once, the
// project chart (`loadProject(root:)`) runs as a job with an "analyzing" block
// shown until it finishes. Closing the window cancels a running project scan.
import { api, withQuery } from "../../../lib/api";
import { type RunningJob, runJob } from "../../../lib/jobs";
import { asWindowContent, openWindow, setWindowTitle } from "../../../lib/ui/windows.svelte";
import type { ComplexityDTO, ComplexityPointDTO } from "./dto";
import ComplexityWindow from "./ComplexityWindow.svelte";

/** What the window shows. Mutated in place; the window component reads it. */
export const complexity = $state<{
  summary: string;
  placeholder: string;
  points: ComplexityPointDTO[];
  analysing: boolean;
}>({ summary: "", placeholder: "", points: [], analysing: false });

let windowId: number | null = null;
let running: RunningJob<ComplexityDTO> | null = null;
let generation = 0;

/** Plots the functions of one file (`path`), or of every source file in the open project when `path` is absent. */
export function openComplexityWindow(target: { path?: string }): void {
  void show(target.path);
}

async function show(path: string | undefined): Promise<void> {
  stopRunning();
  const current = ++generation;
  const id = openWindow({
    key: "ComplexityWindow",
    title: "Complexity distribution",
    width: 760,
    height: 520,
    minWidth: 480,
    minHeight: 320,
    escCloses: true,
    component: asWindowContent(ComplexityWindow),
    onClose: stopRunning,
  });
  windowId = id;
  complexity.points = [];
  complexity.placeholder = "";

  if (path !== undefined) {
    complexity.analysing = false;
    try {
      const dto = await api<ComplexityDTO>("GET", withQuery("/api/complexity", { path }));
      if (current === generation) apply(dto);
    } catch (error) {
      if (current !== generation) return;
      complexity.summary = error instanceof Error ? error.message : String(error);
    }
    return;
  }

  complexity.summary = "Analyzing complexity distribution…";
  complexity.analysing = true;
  const job = runJob<ComplexityDTO>(api<{ jobId: string }>("GET", "/api/complexity"));
  running = job;
  try {
    const outcome = await job.promise;
    if (current !== generation) return;
    running = null;
    if (outcome.status === "cancelled" || !outcome.result) {
      complexity.analysing = false;
      return;
    }
    apply(outcome.result);
  } catch (error) {
    if (current !== generation) return;
    running = null;
    complexity.analysing = false;
    complexity.summary = error instanceof Error ? error.message : String(error);
  }
}

function apply(dto: ComplexityDTO): void {
  complexity.analysing = false;
  complexity.summary = dto.summary;
  complexity.placeholder = dto.placeholder;
  complexity.points = dto.points;
  if (windowId !== null) setWindowTitle(windowId, dto.windowTitle);
}

function stopRunning(): void {
  generation++;
  complexity.analysing = false;
  const job = running;
  running = null;
  if (job) job.cancel().catch(() => undefined);
}
