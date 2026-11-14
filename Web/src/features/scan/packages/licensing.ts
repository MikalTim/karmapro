// Opens the Licensing window (`LicensingWindowController`). It opens even without
// a project; the server then answers with its "no project" report, as AppKit does.
import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import LicensingWindow from "./LicensingWindow.svelte";

export function openLicensingWindow(): void {
  openWindow({
    title: "Project License & Commercial Use Auditor",
    width: 700,
    height: 500,
    escCloses: true,
    component: asWindowContent(LicensingWindow),
  });
}
