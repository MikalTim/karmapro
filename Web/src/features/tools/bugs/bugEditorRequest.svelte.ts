// The bug editor is a sheet of the bug list window (`parent.beginSheet` in BugListWindowController),
// so the list window shows it. Code outside the list asks for it here; the list takes the request
// and opens the sheet. Only one request is pending at a time.
import type { BugDTO } from "./bugModel";

export interface BugEditorOptions {
  /** The report to edit. Without it the editor starts a new report. */
  id?: string;
  /** Called with the saved report, before the editor closes (`onSaved`). */
  onSaved?: (bug: BugDTO) => void;
}

/** The request waiting for the bug list window to take it; null when none is waiting. */
export const bugEditorRequest = $state<{ pending: BugEditorOptions | null }>({ pending: null });

export function openBugEditorWindow(options: BugEditorOptions = {}): void {
  bugEditorRequest.pending = options;
}
