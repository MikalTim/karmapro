// Opens the Search in Files window (`FileSearchWindowController`). The window
// searches the language the main window's popup showed when it opened, so the
// caller passes that name; null or "All Languages" searches every file.
import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import FileSearchWindow from "./FileSearchWindow.svelte";
import { searchWindowTitle } from "./searchModel";

export function openFileSearchWindow(options?: { language?: string | null }): void {
  const language = options?.language ?? null;
  openWindow({
    title: searchWindowTitle(language),
    width: 760,
    height: 520,
    minWidth: 480,
    minHeight: 300,
    escCloses: true,
    component: asWindowContent(FileSearchWindow),
    props: { language },
  });
}
