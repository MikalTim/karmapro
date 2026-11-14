<script lang="ts">
  // The Search in Files window (`FileSearchWindowController`). Every keystroke starts
  // a project-wide search on the server. Only the newest search's answer is shown.
  import { onDestroy } from "svelte";
  import { api } from "../../../lib/api";
  import { runJob, type RunningJob } from "../../../lib/jobs";
  import SearchField from "../../../lib/ui/SearchField.svelte";
  import Table from "../../../lib/ui/Table.svelte";
  import { showFileInMainWindow } from "../../main/navigation";
  import { clickedRow } from "../rowClick";
  import { errorText } from "./errorText";
  import {
    SEARCH_PLACEHOLDER,
    SEARCH_PROMPT_STATUS,
    SEARCH_RUNNING_STATUS,
    matchRows,
    searchColumns,
    searchRequest,
    type SearchMatch,
    type SearchResult,
    type SearchRow,
  } from "./searchModel";

  // The language is the main window's popup as it was when this window opened.
  let { windowId, language }: { windowId: number; language: string | null } = $props();

  let term = $state("");
  let selectedKey = $state<string | null>(null);
  let statusText = $state(SEARCH_PROMPT_STATUS);
  let matches = $state<SearchMatch[]>([]);
  let tableWidth = $state(0);
  let latest = 0;
  let inflight: RunningJob<SearchResult> | undefined;

  const rows = $derived(matchRows(matches));
  const columns = $derived(searchColumns(tableWidth));

  function search(text: string) {
    const ticket = ++latest;
    // The previous search is stale now. Cancel it, and ignore whatever it answers.
    // A cancel that fails only means that search already finished.
    void inflight?.cancel().catch(() => undefined);
    statusText = SEARCH_RUNNING_STATUS;
    const job = runJob<SearchResult>(api<{ jobId: string }>("POST", "/api/search", searchRequest(text, language)));
    inflight = job;
    job.promise.then(
      (outcome) => {
        if (ticket !== latest || !outcome.result) return;
        matches = outcome.result.matches;
        statusText = outcome.result.statusText;
      },
      (error: unknown) => {
        if (ticket === latest) statusText = errorText(error);
      },
    );
  }

  function openRow(row: SearchRow) {
    showFileInMainWindow(row.match.path, row.match.line);
  }

  /** A mouse click on a match opens it, as AppKit's `rowClicked` does. Keyboard moves only select. */
  function openClickedRow(event: MouseEvent) {
    const row = clickedRow(event, rows, (candidate) => candidate.id, selectedKey);
    if (row) openRow(row);
  }

  onDestroy(() => {
    latest++;
    void inflight?.cancel().catch(() => undefined);
  });
</script>

<div class="search-window">
  <div class="field">
    <SearchField bind:value={term} placeholder={SEARCH_PLACEHOLDER} focusOnMount onInput={search} />
  </div>
  <div class="status">{statusText}</div>
  <div class="results" bind:clientWidth={tableWidth} role="presentation" onclick={openClickedRow}>
    <Table {columns} {rows} rowKey={(row) => row.id} rowHeight={20} bind:selectedKey>
      {#snippet cell(row)}
        <span class="match" title={row.match.path}><span class="head">{row.head}</span>{"\t"}{row.body}</span>
      {/snippet}
    </Table>
  </div>
</div>

<style>
  .search-window {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    padding-top: 12px;
    font-family: var(--font-ui);
  }
  .field {
    margin: 0 16px;
  }
  .status {
    margin: 8px 16px 0;
    font-size: 12px;
    color: var(--secondary-label);
  }
  .results {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    margin-top: 8px;
    font: 12px var(--font-mono);
  }
  /* AppKit's results table has no header row. */
  .results :global(.header) {
    display: none;
  }
  .match {
    white-space: pre;
  }
  .head {
    font-weight: 700;
    color: var(--accent);
  }
</style>
