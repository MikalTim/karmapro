<script lang="ts">
  // The security bugs tracker (BugListWindowController): a search field, the
  // report table, the detail panel for the selected report, and the Backup,
  // Import and New Bug buttons. The list follows `bugs.changed`.
  import { onMount } from "svelte";
  import { api, withQuery } from "../../../lib/api";
  import { on } from "../../../lib/events";
  import Table, { type Column } from "../../../lib/ui/Table.svelte";
  import SearchField from "../../../lib/ui/SearchField.svelte";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import {
    bugCellValue,
    bugDetailBody,
    bugDetailMeta,
    messageOf,
    selectionAfterReload,
    severityColor,
    type BugDTO,
    type BugListDTO,
  } from "./bugModel";
  import { backupBugs, deleteBug, importBugs } from "./bugActions";
  import BugEditorSheet from "./BugEditorSheet.svelte";
  import { bugEditorRequest, type BugEditorOptions } from "./bugEditorRequest.svelte";
  // Windows receive their id; the list does not need it itself.
  let { windowId }: { windowId: number } = $props();

  const columns: Column<BugDTO>[] = [
    { id: "id", title: "ID", width: 150, wrap: false },
    { id: "title", title: "Title", width: 260 },
    { id: "severity", title: "Severity", width: 90, wrap: false, style: (bug) => `color:${severityColor(bug.severity)}` },
    {
      id: "exploitability",
      title: "Exploitability",
      width: 105,
      wrap: false,
      style: (bug) => `color:${severityColor(bug.exploitability)}`,
    },
    { id: "package", title: "Package", width: 150 },
    { id: "status", title: "Status", width: 90, wrap: false },
    { id: "created", title: "Created", width: 140, minWidth: 140, wrap: false },
  ];

  let bugs = $state<BugDTO[]>([]);
  let countText = $state("");
  let query = $state("");
  let selectedKey = $state<string | null>(null);
  let editor = $state<BugEditorOptions | null>(null);
  let requestSeq = 0;

  const selected = $derived(bugs.find((bug) => bug.id === selectedKey) ?? null);

  /**
   * Loads the reports matching the search. The selection follows AppKit's table: a reload keeps the
   * selected row index, so the report now at that row is selected. `selectId` (after a save) wins.
   */
  async function reload(selectId?: string): Promise<void> {
    // Answers to older searches are dropped, so the list always shows the latest query.
    const seq = ++requestSeq;
    try {
      const result = await api<BugListDTO>("GET", withQuery("/api/bugs", { query }));
      if (seq !== requestSeq) return;
      selectedKey = selectId ?? selectionAfterReload(bugs, result.bugs, selectedKey);
      bugs = result.bugs;
      countText = result.countText;
    } catch (error) {
      if (seq === requestSeq) await showAlert({ message: messageOf(error), buttons: ["OK"] });
    }
  }

  // A request from outside the list (`openBugEditorWindow`) opens the editor sheet here.
  $effect(() => {
    const pending = bugEditorRequest.pending;
    if (pending === null) return;
    bugEditorRequest.pending = null;
    editor = pending;
  });

  // presentEditor: after a save the list reloads and selects the saved report.
  function openEditor(id?: string): void {
    editor = { id, onSaved: (saved) => void reload(saved.id) };
  }

  async function removeSelected(): Promise<void> {
    const bug = selected;
    if (!bug) return;
    await deleteBug(bug);
    await reload();
  }

  async function runImport(): Promise<void> {
    await importBugs(reload);
  }

  onMount(() => {
    void reload();
    return on("bugs.changed", () => void reload());
  });
</script>

<div class="bugs">
  <div class="top-row">
    <div class="search">
      <SearchField
        bind:value={query}
        placeholder="Search bugs by title, description, severity…"
        onInput={(value) => {
          query = value;
          void reload();
        }}
      />
    </div>
    <span class="status">{countText}</span>
    <button class="btn" title="Export all bug reports to a JSON file" onclick={() => void backupBugs()}>Backup…</button>
    <button class="btn" title="Import bug reports from a JSON backup file" onclick={() => void runImport()}>Import…</button>
    <button class="btn" onclick={() => openEditor()}>New Bug</button>
  </div>

  <div class="grid">
    <Table
      {columns}
      rows={bugs}
      rowKey={(bug) => bug.id}
      autoHeight
      lastColumnFills
      bind:selectedKey
      onDoubleClick={(bug) => openEditor(bug.id)}
    >
      {#snippet cell(bug: BugDTO, column: Column<BugDTO>)}
        <span title={column.id === "title" ? bug.title : undefined}>{bugCellValue(bug, column.id)}</span>
      {/snippet}
    </Table>
  </div>

  <section class="detail">
    <div class="box-title">Bug Detail</div>
    <div class="detail-title">{selected ? selected.title : "No bug selected"}</div>
    <div class="detail-meta" style="color:{selected ? severityColor(selected.severity) : 'var(--secondary-label)'}">
      {selected ? bugDetailMeta(selected) : "Select a bug report to see its full details."}
    </div>
    <div class="detail-body">{selected ? bugDetailBody(selected) : ""}</div>
    <div class="detail-buttons">
      <span class="grow"></span>
      <button class="btn" disabled={!selected} onclick={() => openEditor(selected?.id)}>Edit…</button>
      <button class="btn" disabled={!selected} onclick={() => void removeSelected()}>Delete</button>
    </div>
  </section>
  {#if editor}
    <BugEditorSheet {windowId} id={editor.id} onSaved={editor.onSaved} onClose={() => (editor = null)} />
  {/if}
</div>

<style>
  .bugs {
    height: 100%;
    display: flex;
    flex-direction: column;
    box-sizing: border-box;
    padding: 12px 16px 16px;
    gap: 8px;
    font: 13px var(--font-ui);
    color: var(--label);
    background: var(--window-bg);
  }
  .top-row {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .search {
    flex: 1 1 280px;
    min-width: 280px;
  }
  .status {
    font-size: 12px;
    color: var(--secondary-label);
    white-space: nowrap;
  }
  .grid {
    flex: 1 1 auto;
    min-height: 120px;
    display: flex;
    flex-direction: column;
    font-size: 12px;
  }
  .grid :global(.table) {
    flex: 1;
  }
  .detail {
    flex: none;
    display: flex;
    flex-direction: column;
    gap: 8px;
    box-sizing: border-box;
    border: 1px solid var(--separator);
    border-radius: 6px;
    padding: 12px;
  }
  .box-title {
    font-size: 11px;
    color: var(--secondary-label);
    align-self: flex-start;
  }
  .detail-title {
    font-size: 15px;
    font-weight: 700;
    color: var(--label);
  }
  .detail-meta {
    font-size: 12px;
    white-space: pre-line;
  }
  .detail-body {
    font-size: 13px;
    white-space: pre-wrap;
    max-height: 120px;
    overflow: hidden;
    color: var(--label);
  }
  .detail-buttons {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .grow {
    flex: 1;
  }
</style>
