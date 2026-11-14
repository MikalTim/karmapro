// The openers of the data-flow and backtrace windows. AppKit creates a new controller for each
// action, so each call opens a new window (no singleton key).
import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import { projectState } from "../../main/projectState.svelte";
import BacktraceWindow from "./BacktraceWindow.svelte";
import DataFlowWindow from "./DataFlowWindow.svelte";

/** `DataFlowWindowController(fileURL:functionName:)`: 900 x 700, at least 600 x 400. */
export function openDataFlowWindow(target: { path: string; functionName: string }): void {
  openWindow({
    title: `Dataflow: ${target.functionName} \u2014 ${target.path.slice(target.path.lastIndexOf("/") + 1)}`,
    width: 900,
    height: 700,
    minWidth: 600,
    minHeight: 400,
    escCloses: true,
    component: asWindowContent(DataFlowWindow),
    props: { path: target.path, functionName: target.functionName },
  });
}

/** `BacktraceAnalyserWindowController`: 1000 x 560, at least 660 x 380. Without an open project nothing happens. */
export function openBacktraceWindow(): void {
  if (projectState.root === null) return;
  openWindow({
    title: "Backtrace Analyser",
    width: 1000,
    height: 560,
    minWidth: 660,
    minHeight: 380,
    escCloses: true,
    component: asWindowContent(BacktraceWindow),
  });
}
