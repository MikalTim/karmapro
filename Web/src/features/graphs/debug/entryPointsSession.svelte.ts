// The entry-point finder's session. The server keeps one result set for every
// browser tab, so this store mirrors it: it starts searches, follows their jobs,
// and traces the selected entry. A newer request supersedes the older one, as the
// AppKit window cancels its previous work when a new one starts.
import { api } from "../../../lib/api";
import { runJob, type RunningJob } from "../../../lib/jobs";
import { showAlert } from "../../../lib/ui/alert.svelte";
import { tracingCaption, type EntrySite, type EntryPointsState, type EntryTrace } from "./entryPointsModel";

/** How often the state is read while a search runs, for the progress line. */
const POLL_MS = 250;

export const entryPoints = $state<{
  state: EntryPointsState | null;
  trace: EntryTrace | null;
  /** The caption of a trace in progress; null when none is.  */
  tracing: string | null;
  selectedSiteID: string | null;
  /** Bumped when a search finishes, so the outline expands its categories again (`reload()`). */
  groupsRun: number;
}>({ state: null, trace: null, tracing: null, selectedSiteID: null, groupsRun: 0 });

let searchRun = 0;
let traceRun = 0;
let search: RunningJob<EntryPointsState> | null = null;
let trace: RunningJob<EntryTrace> | null = null;

/** Starts a fresh search, as `EntryPointsWindowController.begin` does on every open. */
export function beginEntrySearch(): void {
  closeEntrySearch();
  entryPoints.state = null;
  entryPoints.trace = null;
  entryPoints.tracing = null;
  entryPoints.selectedSiteID = null;
  const run = ++searchRun;
  void runSearch(run, api<{ jobId: string }>("POST", "/api/entry-points/start"));
}

/** Turns the indirect tier on or off (`toggleIndirect`). The first switch on collects the tier. */
export function setIndirectEntries(on: boolean): void {
  const run = ++searchRun;
  const previous = search;
  search = null;
  if (previous) previous.cancel().catch(() => undefined);
  void runSearch(run, api<{ jobId: string }>("POST", "/api/entry-points/indirect", { on }));
}

/** Traces the flow of the selected entry (`trace(site:)`). Only the newest selection's result is shown. */
export async function traceEntrySite(site: EntrySite): Promise<void> {
  entryPoints.selectedSiteID = site.id;
  const previous = trace;
  if (previous) previous.cancel().catch(() => undefined);
  const run = ++traceRun;
  entryPoints.tracing = site.entryVariable ? tracingCaption(site) : null;
  const job = runJob<EntryTrace>(api<{ jobId: string }>("POST", "/api/entry-points/trace", { siteID: site.id }));
  trace = job;
  try {
    const outcome = await job.promise;
    if (run !== traceRun || !outcome.result) return;
    entryPoints.trace = outcome.result;
    entryPoints.tracing = null;
  } catch (error) {
    if (run !== traceRun) return;
    entryPoints.tracing = null;
    await reportError(error);
  } finally {
    if (run === traceRun) trace = null;
  }
}

/** The window closed: a running search is cancelled, as `windowWillClose` does. */
export function closeEntrySearch(): void {
  searchRun++;
  traceRun++;
  const searchJob = search;
  const traceJob = trace;
  search = null;
  trace = null;
  if (searchJob) searchJob.cancel().catch(() => undefined);
  if (traceJob) traceJob.cancel().catch(() => undefined);
}

async function runSearch(run: number, start: Promise<{ jobId: string }>): Promise<void> {
  const handle = runJob<EntryPointsState>(start);
  search = handle;
  const poll = window.setInterval(() => void refresh(run), POLL_MS);
  try {
    const outcome = await handle.promise;
    if (run === searchRun && outcome.result) {
      applyState(outcome.result);
      entryPoints.groupsRun++;
    }
  } catch (error) {
    if (run === searchRun) await reportError(error);
  } finally {
    window.clearInterval(poll);
    if (run === searchRun) search = null;
  }
}

/** Reads the state while a search runs. A failed read is retried by the next tick; the job reports real failures. */
async function refresh(run: number): Promise<void> {
  if (run !== searchRun) return;
  try {
    const dto = await api<EntryPointsState>("GET", "/api/entry-points");
    if (run === searchRun) applyState(dto);
  } catch {
    return;
  }
}

function applyState(dto: EntryPointsState): void {
  entryPoints.state = dto;
  entryPoints.trace = dto.trace ?? null;
}

async function reportError(error: unknown): Promise<void> {
  await showAlert({ message: error instanceof Error ? error.message : String(error), style: "warning" });
}
