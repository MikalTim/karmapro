// The definition popup (AppKit `DefinitionWindowController`). Each call opens its own window, as AppKit
// creates a new controller per click; the window is not a singleton.
import { asWindowContent, openWindow } from "../../lib/ui/windows.svelte";
import DefinitionWindow from "./DefinitionWindow.svelte";
import { loadDefinition } from "./sourceApi";
import { definitionTitle, errorText } from "./sourceModel";

/** Opens the file that defines the name starting at `nameOffset`, with that definition's line selected. */
export async function openDefinitionWindow(target: { path: string; nameOffset: number }): Promise<void> {
  try {
    const definition = await loadDefinition(target.path, target.nameOffset);
    openDefinitionText(definition.path, definition.text, definition.line);
  } catch (error) {
    // The window shows the reason in place of the text, as AppKit's window does for an unreadable file.
    openDefinitionText(target.path, errorText(error), null);
  }
}

/** Opens the definition window for text already read. `line` is null when the text is an error message. */
export function openDefinitionText(path: string, text: string, line: number | null): void {
  openWindow({
    title: definitionTitle(path),
    width: 640,
    height: 400,
    minWidth: 420,
    minHeight: 240,
    escCloses: true,
    component: asWindowContent(DefinitionWindow),
    props: { path, text, line },
  });
}
