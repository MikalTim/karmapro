// Opens the bug report editor. It is a window rather than the sheet AppKit
// attaches to the list, so it can be opened from anywhere on the page; several
// editors may be open at once, as several controllers can be in AppKit.
import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import type { BugDTO } from "./bugModel";
import BugEditorWindow from "./BugEditorWindow.svelte";

export interface BugEditorOptions {
  /** The report to edit. Without it the editor starts a new report. */
  id?: string;
  /** Called with the saved report, before the editor closes (`onSaved`). */
  onSaved?: (bug: BugDTO) => void;
}

export function openBugEditorWindow(options: BugEditorOptions = {}): void {
  openWindow({
    title: options.id === undefined ? "New Bug Report" : "Edit Bug Report",
    width: 560,
    height: 600,
    escCloses: true,
    component: asWindowContent(BugEditorWindow),
    props: { id: options.id, onSaved: options.onSaved },
  });
}
