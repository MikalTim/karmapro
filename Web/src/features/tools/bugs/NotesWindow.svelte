<script lang="ts">
  // The Notes window (NotesWindowController): every note of the open project in
  // a table. A click opens the note's file at its line in the main window.
  // Export, Import and Import from URL work on `.codenotes` files. The list
  // follows `notes.changed`.
  import { onMount } from "svelte";
  import { api } from "../../../lib/api";
  import { on } from "../../../lib/events";
  import Table, { type Column } from "../../../lib/ui/Table.svelte";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import { showFileInMainWindow } from "../../main/navigation";
  import { messageOf } from "./bugModel";
  import { exportNotes, importNotesFile, importNotesFromURL } from "./notesActions";
  import { noteCellValue, noteRowKey, notesWindowTitle, type NoteDTO, type NotesListDTO } from "./notesModel";
  import { clickedRow } from "../../scan/rowClick";
  import { setWindowTitle } from "../../../lib/ui/windows.svelte";

  // The window id sets the window's own title, which shows the open project's name.
  let { windowId }: { windowId: number } = $props();

  const columns: Column<NoteDTO>[] = [
    { id: "file", title: "File", width: 240 },
    { id: "line", title: "Line", width: 50, align: "right" },
    { id: "text", title: "Note", width: 420 },
  ];

  let notes = $state<NoteDTO[]>([]);
  let statusText = $state("No notes yet.");
  let selectedKey = $state<string | null>(null);
  let importingURL = $state(false);
  let requestSeq = 0;

  async function reload(): Promise<void> {
    const seq = ++requestSeq;
    try {
      const list = await api<NotesListDTO>("GET", "/api/notes");
      if (seq !== requestSeq) return;
      notes = list.notes;
      statusText = list.statusText;
      setWindowTitle(windowId, notesWindowTitle(list.root));
    } catch (error) {
      if (seq === requestSeq) await showAlert({ message: messageOf(error), buttons: ["OK"] });
    }
  }

  async function runImportURL(): Promise<void> {
    importingURL = true;
    try {
      await importNotesFromURL();
    } finally {
      importingURL = false;
      await reload();
    }
  }

  async function runImportFile(): Promise<void> {
    await importNotesFile();
    await reload();
  }

  /** A mouse click on a note opens its file at the note's line, as AppKit's `rowClicked` does. */
  function openClickedNote(event: MouseEvent) {
    const note = clickedRow(event, notes, noteRowKey, selectedKey);
    if (note) showFileInMainWindow(note.path, note.line);
  }

  onMount(() => {
    void reload();
    return on("notes.changed", () => void reload());
  });
</script>

<div class="notes">
  <div class="header">
    <span class="status">{statusText}</span>
    <button class="btn" onclick={() => void exportNotes()}>Export Notes…</button>
    <button class="btn" onclick={() => void runImportFile()}>Import Notes…</button>
    <button class="btn" disabled={importingURL} onclick={() => void runImportURL()}>Import from URL…</button>
  </div>

  <div class="grid" role="presentation" onclick={openClickedNote}>
    <Table
      {columns}
      rows={notes}
      rowKey={noteRowKey}
      bind:selectedKey
    >
      {#snippet cell(note: NoteDTO, column: Column<NoteDTO>)}
        <span
          title={column.id === "file" ? note.path : column.id === "text" ? note.text : undefined}
        >{noteCellValue(note, column.id)}</span>
      {/snippet}
    </Table>
  </div>
</div>

<style>
  .notes {
    height: 100%;
    display: flex;
    flex-direction: column;
    box-sizing: border-box;
    padding: 12px 16px 0;
    gap: 8px;
    font: 13px var(--font-ui);
    color: var(--label);
    background: var(--window-bg);
  }
  .header {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .status {
    flex: 1;
    font-size: 12px;
    color: var(--secondary-label);
  }
  .grid {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    margin: 0 -16px;
  }
  .grid :global(.table) {
    flex: 1;
  }
</style>
