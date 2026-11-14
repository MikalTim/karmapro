<script lang="ts">
  // The ML highlighted-lines list above the source (AppKit `HighlightedLinesViewController`): one row per line the
  // scan flagged, with its line, probability and preview. A click scrolls the source to that line. The owner shows
  // this only when the file has flagged lines.
  import Table, { type Column } from "../../lib/ui/Table.svelte";
  import type { MLLineDTO } from "./sourceApi";
  import { highlightedLinesTitle, probabilityColor, probabilityPercent } from "./sourceModel";

  let {
    lines,
    onSelect,
  }: {
    lines: MLLineDTO[];
    onSelect: (line: number) => void;
  } = $props();

  const columns: Column<MLLineDTO>[] = [
    { id: "line", title: "Line", width: 64, minWidth: 56 },
    { id: "prob", title: "Probability", width: 72, minWidth: 64 },
    { id: "preview", title: "Preview", width: 420, minWidth: 160 },
  ];
</script>

<div class="list">
  <div class="title">{highlightedLinesTitle(lines.length)}</div>
  <div class="table">
    <Table
      {columns}
      rows={lines}
      rowKey={(row) => String(row.line)}
      rowHeight={20}
      onSelect={(row) => {
        if (row) onSelect(row.line);
      }}
    >
      {#snippet cell(row, column)}
        {#if column.id === "line"}
          <span class="mono">{row.line}</span>
        {:else if column.id === "prob"}
          <span class="mono" style="color:{probabilityColor(row.probability)}">{probabilityPercent(row.probability)}%</span>
        {:else}
          <span class="mono">{row.text}</span>
        {/if}
      {/snippet}
    </Table>
  </div>
</div>

<style>
  .list {
    flex: none;
    display: flex;
    flex-direction: column;
    height: 140px;
    border-bottom: 1px solid var(--separator);
  }
  .title {
    flex: none;
    padding: 6px 12px 4px;
    font-size: 12px;
    font-weight: 600;
    color: var(--secondary-label);
  }
  .table {
    flex: 1;
    min-height: 0;
  }
  .mono {
    font: 12px var(--font-mono);
  }
</style>
