<script lang="ts">
  // The Scan Project's Packages window (`PackageScanWindowController`). The
  // server keeps the detected files, the findings, the sort order and the status
  // line. This window shows them and sends the window's actions. Detect and scan
  // are jobs whose result is the new state.
  import { onDestroy, onMount } from "svelte";
  import { api, download } from "../../../lib/api";
  import { runJob } from "../../../lib/jobs";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import { showContextMenu } from "../../../lib/ui/contextMenu.svelte";
  import PopUp from "../../../lib/ui/PopUp.svelte";
  import ProgressBar from "../../../lib/ui/ProgressBar.svelte";
  import Spinner from "../../../lib/ui/Spinner.svelte";
  import Table from "../../../lib/ui/Table.svelte";
  import { openAIWindow } from "../../ai";
  import { showFileInMainWindow } from "../../main/navigation";
  import { clickedRow } from "../rowClick";
  import { errorText } from "./errorText";
  import {
    ASK_AI_TITLE,
    beginRunView,
    failedRunView,
    keepSelectionIndex,
    nextPackageSort,
    packageCellTitle,
    packageColumns,
    packageFilesText,
    packageRows,
    toneColor,
    vulnerabilityQuestion,
    type PackageRow,
    type PackageScanState,
  } from "./packageModel";

  type RunKind = "detect" | "scan";

  let { windowId }: { windowId: number } = $props();

  // Not named `state`: svelte-check reads `$state` as a store subscription to a variable of that name.
  let scanState = $state<PackageScanState | null>(null);
  let apiSource = $state("");
  let selectedKey = $state<string | null>(null);
  // The progress bar shows only for a scan, as in AppKit; a detection shows the spinner alone.
  let runKind = $state<RunKind | null>(null);
  // AppKit enables Ignore only after a click on a row, and a scan start disables it again.
  let ignoreArmed = $state(false);
  let closed = false;
  const RUNNING_POLL_MS = 500;
  // Bumped whenever a state is applied, so a progress refresh answered after the
  // final state arrived is dropped.
  let generation = 0;

  const rows = $derived(packageRows(scanState?.findings ?? []));
  const columns = packageColumns(0).map((column) => ({ ...column, wrap: column.id === "msg" }));
  const ignoreEnabled = $derived(scanState !== null && !scanState.busy && ignoreArmed && selectedKey !== null);

  function apply(next: PackageScanState) {
    generation++;
    selectedKey = keepSelectionIndex(rows, selectedKey, packageRows(next.findings));
    scanState = next;
  }

  async function refresh() {
    const started = generation;
    const next = await api<PackageScanState>("GET", "/api/packages");
    if (!closed && started === generation) apply(next);
  }

  async function run(kind: RunKind, start: Promise<{ jobId: string }>) {
    if (!scanState) return;
    runKind = kind;
    scanState = beginRunView(scanState);
    try {
      // A missed progress refresh is corrected by the job's final result.
      const outcome = await runJob<PackageScanState>(start, () => void refresh().catch(() => undefined)).promise;
      if (!closed && outcome.result) apply(outcome.result);
    } catch (error) {
      if (!closed) {
        await refresh().catch(() => undefined);
        if (!closed && scanState) scanState = failedRunView(scanState, errorText(error));
      }
    } finally {
      runKind = null;
    }
  }

  /** Shows a scan that another window started, until the server reports that it has finished. */
  async function followRunningScan(initial: PackageScanState) {
    scanState = initial;
    runKind = "scan";
    let next = initial;
    while (next.busy && !closed) {
      await new Promise((resolve) => setTimeout(resolve, RUNNING_POLL_MS));
      if (closed) return;
      next = await api<PackageScanState>("GET", "/api/packages");
      apply(next);
    }
    runKind = null;
  }

  onMount(async () => {
    const initial = await api<PackageScanState>("GET", "/api/packages");
    apiSource = initial.selectedApiSource;
    scanState = initial;
    if (initial.busy) {
      // The server keeps one scan for every window. A scan that an earlier window started is still
      // running, so this window follows it until it ends, instead of starting a detection the server refuses.
      await followRunningScan(initial);
      return;
    }
    await run("detect", api<{ jobId: string }>("POST", "/api/packages/detect"));
  });

  onDestroy(() => {
    closed = true;
  });

  function scan() {
    ignoreArmed = false;
    void run("scan", api<{ jobId: string }>("POST", "/api/packages/scan", { apiSource }));
  }

  async function ignoreSelected() {
    const row = rows.find((candidate) => candidate.id === selectedKey);
    if (!row) return;
    apply(await api<PackageScanState>("POST", "/api/packages/ignore", { key: row.finding.key, ignored: true }));
  }

  async function sortBy(clicked: string, tableAscending: boolean) {
    if (!scanState) return;
    const next = nextPackageSort(scanState, clicked, tableAscending);
    apply(await api<PackageScanState>("POST", "/api/packages/sort", next));
  }

  async function exportScan() {
    try {
      await download("/api/packages/export", { fallbackName: "KarmaPro-packages.sarif.json" });
    } catch (error) {
      await showAlert({ message: "Export Failed", informative: errorText(error), style: "warning", buttons: ["OK"] });
    }
  }

  function openRow(row: PackageRow) {
    showFileInMainWindow(row.finding.path, row.finding.line);
  }

  /** A mouse click on a finding opens it, as AppKit's `rowClicked` does. Keyboard moves only select. */
  function openClickedRow(event: MouseEvent) {
    const row = clickedRow(event, rows, (candidate) => candidate.id, selectedKey);
    if (!row) return;
    ignoreArmed = true;
    openRow(row);
  }

  function rowMenu(row: PackageRow | null, event: MouseEvent) {
    if (!row) return;
    ignoreArmed = true;
    showContextMenu(event, [
      { title: ASK_AI_TITLE, action: () => openAIWindow({ prompt: vulnerabilityQuestion(row.finding) }) },
    ]);
  }
</script>

{#if scanState}
  <div class="packages">
    <p class="description">{scanState.descriptionText}</p>

    <div class="api-row">
      <span class="caption">API source:</span>
      <PopUp
        items={scanState.apiSources.map((source) => ({ title: source.title, value: source.id }))}
        bind:value={apiSource}
      />
    </div>

    <div class="caption files-caption">Package files detected:</div>
    <pre class="files">{packageFilesText(scanState)}</pre>
    <div class="privacy">{scanState.privacyNote}</div>

    <div class="status-row">
      <div class="status" style="color:{toneColor(scanState.statusTone)}">{scanState.statusText}</div>
      {#if scanState.busy}<Spinner size={14} />{/if}
      <button
        class="small"
        disabled={!ignoreEnabled}
        title="Hide this finding (persisted across sessions)"
        onclick={ignoreSelected}>Ignore issue</button
      >
      <button
        class="small export"
        disabled={!scanState.exportEnabled}
        title="Save the rows shown in the table as a SARIF file"
        onclick={exportScan}>Export Scan</button
      >
      <button
        class="small"
        disabled={!scanState.scanEnabled}
        title="Re-detect package files and query the selected source"
        onclick={scan}>Scan</button
      >
    </div>

    {#if runKind === "scan"}
      <div class="progress"><ProgressBar value={scanState.progress} /></div>
    {/if}

    <div class="table-wrap" role="presentation" onclick={openClickedRow}>
      <Table
        {columns}
        {rows}
        rowKey={(row) => row.id}
        bind:selectedKey
        rowHeight={28}
        autoHeight
        lastColumnFills
        sortKey={scanState.sortKey}
        ascending={scanState.sortAscending}
        onSort={sortBy}
        onContextMenu={rowMenu}
      >
        {#snippet cell(row, column)}
          <span title={packageCellTitle(row.finding, column.id)}>{column.value?.(row) ?? ""}</span>
        {/snippet}
      </Table>
    </div>
  </div>
{/if}

<style>
  .packages {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    padding-top: 14px;
    font-family: var(--font-ui);
  }
  .description {
    margin: 0 16px;
    font-size: 12px;
    line-height: 1.35;
    color: var(--secondary-label);
  }
  .api-row {
    display: flex;
    align-items: center;
    gap: 6px;
    margin: 10px 16px 0;
  }
  .caption {
    font-size: 12px;
    color: var(--label);
  }
  .files-caption {
    margin: 12px 16px 4px;
  }
  .files {
    flex: none;
    height: 96px;
    box-sizing: border-box;
    margin: 0 16px;
    padding: 6px;
    overflow: auto;
    background: var(--text-bg);
    border: 1px solid var(--bezel-border);
    border-radius: 4px;
    font: 11px/1.35 var(--font-mono);
    color: var(--label);
    white-space: pre-wrap;
    user-select: text;
  }
  .privacy {
    margin: 8px 16px 0;
    font-size: 11px;
    color: var(--system-orange);
  }
  .status-row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 10px 16px 0;
  }
  .status {
    flex: 1;
    min-width: 0;
    font-size: 12px;
  }
  .small {
    flex: none;
    min-height: 19px;
    padding: 1px 10px;
    font: 11px var(--font-ui);
    color: var(--label);
    background: var(--bezel);
    border: 1px solid var(--bezel-border);
    border-radius: 5px;
  }
  .small:hover:not(:disabled) {
    background: var(--bezel-hover);
  }
  .small:disabled {
    opacity: 0.45;
  }
  .small.export {
    background: var(--system-orange);
  }
  .progress {
    display: flex;
    margin: 8px 16px 0;
  }
  .table-wrap {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    margin-top: 6px;
    font-size: 12px;
  }
</style>
