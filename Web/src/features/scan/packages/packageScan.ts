// Opens the Scan Project's Packages window (`PackageScanWindowController`) from
// the Packages menu. Without an open project it shows the same alert AppKit does
// instead of the window.
import { api } from "../../../lib/api";
import { showAlert } from "../../../lib/ui/alert.svelte";
import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import PackageScanWindow from "./PackageScanWindow.svelte";

interface ProjectInfo {
  root: string | null;
}

export async function openPackageScanWindow(): Promise<void> {
  const project = await api<ProjectInfo>("GET", "/api/project");
  if (project.root === null) {
    await showAlert({
      message: "No Project Folder Open",
      informative:
        "Open a project folder first so its dependency manifests and lockfiles can be detected, then run the package scan again.",
      style: "warning",
      buttons: ["OK"],
    });
    return;
  }
  openWindow({
    title: "Scan Project's Packages",
    width: 1120,
    height: 660,
    minWidth: 940,
    minHeight: 560,
    escCloses: true,
    component: asWindowContent(PackageScanWindow),
  });
}
