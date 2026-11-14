// What the Security Scan window's buttons and the toolbar do on the server. An action sends its
// request and does nothing else: the server announces the change with `scan.changed`, and the store
// fetches the new state. Errors are shown in an alert.
import { api, ApiError, download } from "../../../lib/api";
import { showAlert } from "../../../lib/ui/alert.svelte";
import { promptForDirectory } from "../../main/navigation";
import {
  closeCancel,
  errorText,
  nextSort,
  type FindingDTO,
  type ScanPromptDTO,
  type SortChoice,
} from "./scanModel";
import { reportScanError, scanView } from "./scanStore.svelte";

/**
 * The server answers 400 to a scan request that cannot run yet: no project is open (scan start,
 * prompt), or no scan has run (rescan).
 */
export function isBadRequest(error: unknown): boolean {
  return error instanceof ApiError && error.status === 400;
}

/** `securityScanClicked` without a project: "No Folder Open". Its first button opens the folder picker. */
export async function askForFolder(): Promise<void> {
  const choice = await showAlert({
    message: "No Folder Open",
    informative: "Open a source folder before running a security scan.",
    buttons: ["Open Folder", "Cancel"],
    style: "informational",
  });
  if (choice === 0) await promptForDirectory();
}

/** "Also run an AI scan?". Resolves true for the first button, "Yes, analyse with AI". */
export async function askRunAIScan(): Promise<boolean> {
  const prompt = await api<ScanPromptDTO>("GET", "/api/scan/prompt");
  const choice = await showAlert({
    message: prompt.message,
    informative: prompt.informative,
    buttons: prompt.buttons,
    style: "informational",
  });
  return choice === 0;
}

/** Scans the open project, or shows its cached result when no AI pass is wanted. */
export async function startScan(wantsAI: boolean): Promise<void> {
  await api("POST", "/api/scan/start", { wantsAI });
}

/** "Rescan". Before any scan has run it does nothing, as the app's Rescan does. */
export function rescan(): void {
  api("POST", "/api/scan/rescan").catch((error: unknown) => {
    if (!isBadRequest(error)) reportScanError(error);
  });
}

/** "Ignore issue": hides the selected finding, and keeps it hidden across sessions. */
export function ignoreFinding(row: FindingDTO): void {
  api("POST", "/api/scan/ignore", { key: row.key, ignored: true }).catch(reportScanError);
}

/** A header click. The server sorts the rows; the arrow on the header follows once it has. */
export function sortBy(prototype: SortChoice): void {
  const next = nextSort(scanView.sort, prototype);
  api("POST", "/api/scan/sort", { keys: [next] })
    .then(() => {
      scanView.sort = next;
    })
    .catch(reportScanError);
}

/** "Export Scan": the SARIF file of the rows shown, saved through the browser. */
export function exportScan(): void {
  download("/api/scan/export", { fallbackName: "KarmaPro-scan.sarif.json" }).catch((error: unknown) => {
    void showAlert({ message: "Export Failed", informative: errorText(error), style: "warning" });
  });
}

/** "Triage (AI)": the confirmation first, then the pass over every finding. */
export async function triageWithAI(): Promise<void> {
  try {
    const prompt = await api<ScanPromptDTO>("GET", "/api/scan/triage-prompt");
    const choice = await showAlert({
      message: prompt.message,
      informative: prompt.informative,
      buttons: prompt.buttons,
      style: "informational",
    });
    if (choice === 0) await api("POST", "/api/scan/triage", { action: "start" });
  } catch (error) {
    reportScanError(error);
  }
}

/** Closing the window stops what closing the app's window stops (`windowWillClose`). */
export function closeScanWindow(): void {
  const action = closeCancel(scanView.state);
  if (action === "cancelScan") api("POST", "/api/scan/cancel").catch(reportScanError);
  if (action === "cancelTriage") api("POST", "/api/scan/triage", { action: "cancel" }).catch(reportScanError);
}
