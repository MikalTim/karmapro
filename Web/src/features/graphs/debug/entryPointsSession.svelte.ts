// The entry-point finder's session. The server keeps one result set for every
// browser tab, so this store mirrors it: it starts searches, follows their jobs,
// and traces the selected entry. A newer request supersedes the older one, as the
// AppKit window cancels its previous work when a new one starts.
import { api } from "../../../lib/api";
import { trackJob, type JobHandle } from "../../../lib/jobs";
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
let search: JobHandle<EntryPointsState> | null = null;

/** Starts a fresh search, as `EntryPointsWindowController.begin` does on every open. */
export function beginEntrySearch(): void {
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
  void runSearch(run, api<{ jobId: string }>("POST", "/api/entry-points/indirect", { on }));
}

/** Traces the flow of the selected entry (`trace(site:)`). Only the newest selection's result is shown. */
export async function traceEntrySite(site: EntrySite): Promise<void> {
  entryPoints.selectedSiteID = site.id;
  const run = ++traceRun;
  entryPoints.tracing = site.entryVariable ? tracingCaption(site) : null;
  try {
    const started = await api<{ jobId: string }>("POST", "/api/entry-points/trace", { siteID: site.id });
    const outcome = await trackJob<EntryTrace>(started.jobId).promise;
    if (run !== traceRun || !outcome.result) return;
    entryPoints.trace = outcome.result;
    entryPoints.tracing = null;
  } catch (error) {
    if (run !== traceRun) return;
    entryPoints.tracing = null;
    await reportError(error);
  }
}

/** The window closed: a running search is cancelled, as `windowWillClose` does. */
export function closeEntrySearch(): void {
  searchRun++;
  traceRun++;
  if (search && entryPoints.state?.busy) {
    // A failed cancel leaves the search to finish on its own; nothing is shown for it.
    search.cancel().catch(() => undefined);
  }
  search = null;
}

async function runSearch(run: number, start: Promise<{ jobId: string }>): Promise<void> {
  let handle: JobHandle<EntryPointsState>;
  try {
    const started = await start;
    if (run !== searchRun) return;
    handle = trackJob<EntryPointsState>(started.jobId);
  } catch (error) {
    if (run === searchRun) await reportError(error);
    return;
  }
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
  }
}

/** Reads the state while a search runs. A failed read is retried by the next tick; the job reports real failures. */
async function refresh(run: number): Promise<void> {
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
