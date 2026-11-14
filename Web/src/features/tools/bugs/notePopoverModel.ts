// The note popover's rules: its heading, which request a Save sends, and when
// Remove is offered. Blank text removes the note, as the popover's Save does.

/** `GET /api/notes/line` (`{"text": String | null}`). */
export interface NoteTextDTO {
  text: string | null;
}

/** Where the popover points: a DOMRect, or a bare point (then the size is zero). */
export interface NoteAnchor {
  x: number;
  y: number;
  width?: number;
  height?: number;
}

export type NoteSaveAction = { kind: "save"; text: string } | { kind: "remove" };

/** The popover title (`NotePopoverController.loadView`). The dash is an em dash. */
export function noteHeading(line: number): string {
  return `Note — Line ${line}`;
}

/** The file name under the title: the path's last component. */
export function fileNameOf(path: string): string {
  return path.slice(path.lastIndexOf("/") + 1);
}

/**
 * Save (`saveClicked`): text that is blank once trimmed removes the note; any
 * other text is saved exactly as typed, untrimmed.
 */
export function noteSaveAction(text: string): NoteSaveAction {
  return text.trim() === "" ? { kind: "remove" } : { kind: "save", text };
}

/** Remove is offered only when the line already had a note when the popover opened (`viewDidLoad`). */
export function removeIsOffered(storedNote: string | null): boolean {
  return storedNote !== null;
}

/** The rectangle the popover points at, with zero size for a bare point. */
export function anchorRect(anchor: NoteAnchor): { x: number; y: number; width: number; height: number } {
  return { x: anchor.x, y: anchor.y, width: anchor.width ?? 0, height: anchor.height ?? 0 };
}
