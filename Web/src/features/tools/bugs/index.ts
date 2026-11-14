// The bug tracker, the bug editor, the Notes window and the line note popover.
import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import BugListWindow from "./BugListWindow.svelte";
import NotesWindow from "./NotesWindow.svelte";

export { openBugEditorWindow, type BugEditorOptions } from "./openBugEditor";
export { default as NotePopover } from "./NotePopover.svelte";

/** The security bugs tracker. AppKit keeps one stored controller, so opening it again focuses it. */
export function openBugListWindow(): void {
  openWindow({
    key: "BugListWindow",
    title: "Security bugs tracker",
    width: 920,
    height: 640,
    minWidth: 720,
    minHeight: 440,
    escCloses: true,
    component: asWindowContent(BugListWindow),
  });
}

/** The Notes window. AppKit keeps one stored controller, so opening it again focuses it. */
export function openNotesWindow(): void {
  openWindow({
    key: "NotesWindow",
    title: "Notes",
    width: 760,
    height: 520,
    minWidth: 480,
    minHeight: 300,
    escCloses: true,
    component: asWindowContent(NotesWindow),
  });
}
