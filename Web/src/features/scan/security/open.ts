import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import ScanWindow from "./ScanWindow.svelte";
import { askForFolder, askRunAIScan, closeScanWindow, isBadRequest, startScan } from "./scanActions";
import { followScan, reportScanError } from "./scanStore.svelte";

/** Opens the one Security Scan window. The app keeps a single stored controller, so this is a singleton. */
function showScanWindow(): void {
  openWindow({
    key: "ScanWindow",
    title: "Security Scan",
    width: 1100,
    height: 560,
    minWidth: 1000,
    minHeight: 560,
    escCloses: true,
    component: asWindowContent(ScanWindow),
    onClose: closeScanWindow,
  });
}

/**
 * The Security Scanner toolbar button. Without `options` it first asks "Also run an AI scan?", as
 * `securityScanClicked` does. With `options` it starts the scan at once. The window opens after
 * the scan has started, so a missing folder never shows an empty window.
 */
export async function openScanWindow(options?: { wantsAI?: boolean }): Promise<void> {
  try {
    await followScan();
    const wantsAI = options ? (options.wantsAI ?? false) : await askRunAIScan();
    await startScan(wantsAI);
  } catch (error) {
    // The server answers 400 here only when no project is open.
    if (isBadRequest(error)) {
      await askForFolder();
      return;
    }
    reportScanError(error);
    return;
  }
  showScanWindow();
}

/** Shows the pull request scan that the server has already started. It starts nothing itself. */
export function openPRScanWindow(): void {
  followScan().catch(reportScanError);
  showScanWindow();
}
