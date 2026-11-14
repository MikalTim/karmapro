<script lang="ts">
  // The Security Scan window (`ScanWindowController`): the status line with the AI phase and the
  // "(thinking)" indicator, the buttons, the progress bar, and the findings table. Everything it
  // shows comes from the server's state (see scanStore.svelte.ts).
  import ProgressBar from "../../../lib/ui/ProgressBar.svelte";
  import Spinner from "../../../lib/ui/Spinner.svelte";
  import { setWindowTitle } from "../../../lib/ui/windows.svelte";
  import { showFileInMainWindow } from "../../main/navigation";
  import { exportScan, ignoreFinding, rescan, sortBy, triageWithAI } from "./scanActions";
  import { rowAt, statusParts, triageLook, visibleColumns, type ColumnSpec } from "./scanModel";
  import ScanResultsTable from "./ScanResultsTable.svelte";
  import { scanView } from "./scanStore.svelte";

  let { windowId }: { windowId: number } = $props();

  const view = $derived(scanView.state);
  const columns = $derived(visibleColumns(view));
  const status = $derived(statusParts(view));
  const progress = $derived(view.progress ?? null);
  const triage = $derived(triageLook(view.canTriage));
  let selected = $state<number | null>(null);
  const selectedRow = $derived(rowAt(view.rows, selected));

  $effect(() => {
    setWindowTitle(windowId, view.title);
  });

  /** A click on a row opens its file at the finding's line, as `rowClicked` does. */
  function openRow(index: number) {
    const row = rowAt(view.rows, index);
    if (row) showFileInMainWindow(row.path, row.line);
  }

  function headerClicked(column: ColumnSpec) {
    if (column.sort) sortBy(column.sort);
  }

  function ignoreSelected() {
    if (selectedRow) ignoreFinding(selectedRow);
  }
</script>

<div class="scan-window">
  <div class="bar">
    <div class="status">
      <div class="text" role="status">
        {#each status as part}<span style="color:{part.color}; font-weight:{part.weight}; font-size:{part.size}px">{part.text}</span>{/each}
      </div>
      {#if view.aiThinking}
        <span class="thinking">(thinking)</span>
        <span class="spinner"><Spinner size={12} /></span>
      {/if}
    </div>
    <div class="actions">
      <button
        type="button"
        class="btn small triage"
        disabled={!view.canTriage}
        style="background:{triage.background}; opacity:{triage.opacity}"
        title="Ask the AI model to check every finding for validity"
        onclick={triageWithAI}>Triage (AI)</button
      >
      <button
        type="button"
        class="btn small"
        disabled={!selectedRow}
        title="Hide this finding (persisted across sessions)"
        onclick={ignoreSelected}>Ignore issue</button
      >
      <button
        type="button"
        class="btn small export"
        disabled={!view.canExport}
        style="background:var(--system-orange)"
        title="Save the results shown in the table as a SARIF file"
        onclick={exportScan}>Export Scan</button
      >
      <button
        type="button"
        class="btn small"
        disabled={!view.canRescan}
        title="Re-run the scan for the current project"
        onclick={rescan}>Rescan</button
      >
    </div>
  </div>
  {#if progress !== null}
    <div class="progress">
      <ProgressBar value={view.progressIndeterminate ? null : progress} />
    </div>
  {/if}
  <ScanResultsTable
    {columns}
    rows={view.rows}
    bind:selected
    sort={scanView.sort}
    onHeaderClick={headerClicked}
    onRowClick={openRow}
  />
</div>

<style>
  .scan-window {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    background: var(--window-bg);
  }
  .bar {
    flex: none;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 16px;
  }
  .status {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
  }
  .text {
    min-width: 0;
    line-height: 16px;
  }
  .thinking {
    margin-left: 8px;
    font-size: 11px;
    font-weight: 600;
    color: var(--system-purple);
    white-space: nowrap;
  }
  .spinner {
    margin-left: 4px;
    display: inline-flex;
  }
  .actions {
    flex: none;
    display: flex;
    gap: 8px;
  }
  .btn.triage {
    color: #000;
  }
  .btn.triage:disabled {
    color: #000;
  }
  .btn.export:disabled {
    opacity: 0.5;
  }
  .progress {
    flex: none;
    padding: 0 16px 8px;
  }
</style>
