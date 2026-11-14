// The Security Scan state, shared by the window and by the actions. The server pushes `scan.changed`
// after every change to the scan, so this store fetches the state again then. It stays subscribed
// after the window closes, so an alert raised by a scan still appears, as the app's alerts do.
import { api } from "../../../lib/api";
import { on, onConnection } from "../../../lib/events";
import { showAlert } from "../../../lib/ui/alert.svelte";
import { EMPTY_STATE, errorText, pendingNotice, type SortChoice, type StateDTO } from "./scanModel";

export const scanView = $state<{ state: StateDTO; sort: SortChoice | null }>({ state: EMPTY_STATE, sort: null });

let requested = 0;
let applied = 0;
let noticeSeen: number | null = null;
let subscribed = false;

function applyState(next: StateDTO): void {
  const notice = pendingNotice(next.notice, noticeSeen);
  noticeSeen = Math.max(noticeSeen ?? 0, next.notice?.id ?? 0);
  scanView.state = next;
  if (notice) void showAlert({ message: notice.title, informative: notice.message, style: "warning" });
}

/**
 * Fetches the state. Only the newest request is applied, so an answer that arrives late cannot
 * overwrite a newer one.
 */
export async function refreshScan(): Promise<void> {
  const sequence = ++requested;
  const next = await api<StateDTO>("GET", "/api/scan");
  if (sequence < applied) return;
  applied = sequence;
  applyState(next);
}

/** Shows an unexpected failure. The title is the window's own, since the app has no wording for it. */
export function reportScanError(error: unknown): void {
  void showAlert({ message: "Security Scan", informative: errorText(error), style: "warning" });
}

/**
 * Subscribes to the scan events once per page, then fetches the current state. The first state
 * seeds the alert memory, so a notice from earlier is not repeated.
 */
export function followScan(): Promise<void> {
  if (!subscribed) {
    subscribed = true;
    on("scan.changed", () => {
      refreshScan().catch(reportScanError);
    });
    onConnection((open) => {
      if (open) refreshScan().catch(reportScanError);
    });
  }
  return refreshScan();
}
