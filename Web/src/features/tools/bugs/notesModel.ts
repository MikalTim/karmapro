// The Notes window's rules: what a row shows and how rows are told apart. The
// server sends the list (already filtered to the open project) and keeps the file.

/** One note as the server sends it (`NotesService.NoteDTO`). */
export interface NoteDTO {
  path: string;
  relativePath: string;
  /** The File column: the file name. */
  file: string;
  /** 1-based line. */
  line: number;
  text: string;
}

/** `GET /api/notes` (`NotesService.ListDTO`). */
export interface NotesListDTO {
  root: string | null;
  /** "No notes yet.", "1 note" or "N notes". */
  statusText: string;
  notes: NoteDTO[];
}

/** The outcome of an import; `title` and `message` are the alert the window shows (`NotesService.ImportResultDTO`). */
export interface NotesImportResultDTO {
  count: number;
  title: string;
  message: string;
}

/** The text of one table cell in the Notes table. Unknown columns show nothing. */
export function noteCellValue(note: NoteDTO, columnId: string): string {
  switch (columnId) {
    case "file":
      return note.file;
    case "line":
      return String(note.line);
    case "text":
      return note.text;
    default:
      return "";
  }
}

/** One note per file line, so the path and line identify a row. */
export function noteRowKey(note: NoteDTO): string {
  return `${note.path}:${note.line}`;
}

/** The window's title: "Notes", and "Notes — <project name>" once a project is open (`notesClicked`). */
export function notesWindowTitle(root: string | null): string {
  if (root === null) return "Notes";
  return `Notes \u2014 ${root.slice(root.lastIndexOf("/") + 1)}`;
}
