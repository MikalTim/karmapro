// The two ML windows that the main window's menu opens. AppKit keeps one
// `MLTrainingWindowController` and one `MLScanWindowController` in the main
// window and shows them again, so each is a singleton keyed by its component name.
import { api } from "../../../lib/api";
import { showAlert } from "../../../lib/ui/alert.svelte";
import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import MLScanWindow from "./MLScanWindow.svelte";
import MLTrainingWindow from "./MLTrainingWindow.svelte";
import { NO_PROJECT_FOR_SCAN, type ProjectRootDTO, hasProjectRoot } from "./mlModel";

export function openMLTrainingWindow(): void {
  openWindow({
    key: "MLTrainingWindow",
    title: "Train Bayesian Classifier",
    width: 620,
    height: 400,
    minWidth: 560,
    minHeight: 360,
    escCloses: true,
    component: asWindowContent(MLTrainingWindow),
  });
}

/** `mlScanClicked`: without an open folder the menu shows the "No Folder Open" alert and no window. */
export async function openMLScanWindow(): Promise<void> {
  const project = await api<ProjectRootDTO>("GET", "/api/project");
  if (!hasProjectRoot(project)) {
    await showAlert(NO_PROJECT_FOR_SCAN);
    return;
  }
  openWindow({
    key: "MLScanWindow",
    title: "ML Project Scan",
    width: 560,
    height: 320,
    minWidth: 480,
    minHeight: 300,
    escCloses: true,
    component: asWindowContent(MLScanWindow),
  });
}
