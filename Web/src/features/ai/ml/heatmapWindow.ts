// Opens the ML scan heatmap. AppKit keeps one `HeatmapWindowController` and
// shows it again after each scan, so the window is a singleton keyed by its
// component name. Kept apart from `mlWindows.ts`: the scan window opens the
// heatmap, and the heatmap must not import the scan window back.
import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import HeatmapWindow from "./HeatmapWindow.svelte";

export function openHeatmapWindow(): void {
  openWindow({
    key: "HeatmapWindow",
    title: "ML Scan Heatmap",
    width: 920,
    height: 620,
    minWidth: 640,
    minHeight: 420,
    escCloses: true,
    component: asWindowContent(HeatmapWindow),
  });
}
