<script lang="ts">
  // The Security Scan results table (`ScanWindowController`'s NSTableView). The shared `Table` has one
  // fixed row height, but the Finding column wraps and the row grows with its text, as the AppKit rows
  // do (`usesAutomaticRowHeights`). Each row is a CSS grid row, and `content-visibility` lets the
  // browser skip the rows that are off screen.
  import { tick } from "svelte";
  import { cellFor, type ColumnId, type ColumnSpec, type FindingDTO, type SortChoice } from "./scanModel";

  let {
    columns,
    rows,
    selected = $bindable(null),
    sort,
    onHeaderClick,
    onRowClick,
  }: {
    columns: ColumnSpec[];
    rows: FindingDTO[];
    /** The selected row's index, as NSTableView keeps its selection. */
    selected?: number | null;
    sort: SortChoice | null;
    onHeaderClick: (column: ColumnSpec) => void;
    /** A mouse click on a row, after it is selected. Keyboard moves only select. */
    onRowClick: (index: number) => void;
  } = $props();

  const MIN_COLUMN_WIDTH = 30;

  /** Widths the user dragged to. The Finding column takes the rest of the width unless it was dragged. */
  let dragged = $state<Partial<Record<ColumnId, number>>>({});
  let scroller: HTMLDivElement | undefined = $state();
  let viewWidth = $state(0);

  const widths = $derived.by(() => {
    const fixed = columns.reduce(
      (sum, column) => (column.id === "msg" ? sum : sum + (dragged[column.id] ?? column.width)),
      0,
    );
    return columns.map(
      (column) => dragged[column.id] ?? (column.id === "msg" ? Math.max(MIN_COLUMN_WIDTH, viewWidth - fixed) : column.width),
    );
  });
  const total = $derived(widths.reduce((sum, width) => sum + width, 0));
  const template = $derived(widths.map((width) => `${width}px`).join(" "));

  function startResize(index: number, event: PointerEvent, handle: HTMLElement) {
    event.preventDefault();
    event.stopPropagation();
    const column = columns[index];
    const startX = event.clientX;
    const startWidth = widths[index];
    handle.setPointerCapture(event.pointerId);
    const move = (e: PointerEvent) => {
      dragged[column.id] = Math.max(MIN_COLUMN_WIDTH, startWidth + e.clientX - startX);
    };
    const up = () => {
      handle.removeEventListener("pointermove", move);
      handle.removeEventListener("pointerup", up);
    };
    handle.addEventListener("pointermove", move);
    handle.addEventListener("pointerup", up);
  }

  function keydown(event: KeyboardEvent) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    event.preventDefault();
    if (rows.length === 0) return;
    const current = selected ?? (event.key === "ArrowDown" ? -1 : rows.length);
    const next = event.key === "ArrowDown" ? Math.min(rows.length - 1, current + 1) : Math.max(0, current - 1);
    selected = next;
    void tick().then(() => {
      scroller?.querySelector(`[data-row="${next}"]`)?.scrollIntoView({ block: "nearest" });
    });
  }

  /** A click on a row selects it and opens it, as `rowClicked` does. The row is found from its index. */
  function rowClick(event: MouseEvent) {
    if (!(event.target instanceof Element)) return;
    const index = event.target.closest<HTMLElement>("[data-row]")?.dataset.row;
    if (index === undefined) return;
    selected = Number(index);
    onRowClick(Number(index));
  }
</script>

<div class="scan-table">
  <div class="scroll" bind:this={scroller} bind:clientWidth={viewWidth} role="grid" tabindex="0" onkeydown={keydown}>
    <div class="grid" role="presentation" style="width:{total}px" onclick={rowClick}>
      <div class="head" role="row" style="grid-template-columns:{template}">
        {#each columns as column, index (column.id)}
          <div
            class="th"
            role="columnheader"
            tabindex="-1"
            style="text-align:{column.align}"
            class:sortable={column.sort !== undefined}
            onclick={() => onHeaderClick(column)}
            onkeydown={(event) => event.key === "Enter" && onHeaderClick(column)}
          >
            <span class="title">{column.title}</span>
            {#if sort && column.sort?.key === sort.key}
              <span class="arrow">{sort.ascending ? "\u25B2" : "\u25BC"}</span>
            {/if}
            <div
              class="grip"
              role="presentation"
              onpointerdown={(event) => startResize(index, event, event.currentTarget)}
              onclick={(event) => event.stopPropagation()}
            ></div>
          </div>
        {/each}
      </div>
      {#each rows as row, index}
        <div
          class="tr"
          class:alt={index % 2 === 1}
          class:selected={selected === index}
          data-row={index}
          role="row"
          aria-selected={selected === index}
          style="grid-template-columns:{template}"
        >
          {#each columns as column (column.id)}
            {@const cell = cellFor(row, column.id)}
            <div
              class="td"
              class:wrap={column.id === "msg"}
              role="gridcell"
              style="text-align:{column.align}"
              title={cell.tooltip ?? undefined}
            >
              {#each cell.parts as part}<span style="color:{part.color}; font-weight:{part.weight}; font-size:{part.size}px">{part.text}</span>{/each}
            </div>
          {/each}
        </div>
      {/each}
    </div>
  </div>
</div>

<style>
  .scan-table {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }
  .scroll {
    flex: 1;
    min-height: 0;
    overflow: auto;
    background: var(--control-bg);
    border: 1px solid rgba(255, 255, 255, 0.1);
    outline: none;
  }
  .grid {
    position: relative;
  }
  .head {
    position: sticky;
    top: 0;
    z-index: 1;
    display: grid;
    height: 22px;
    background: #343436;
    border-bottom: 1px solid rgba(0, 0, 0, 0.5);
  }
  .th {
    position: relative;
    padding: 0 6px;
    line-height: 22px;
    font-size: 11px;
    color: var(--secondary-label);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    border-right: 1px solid rgba(255, 255, 255, 0.07);
  }
  .th.sortable:hover {
    color: var(--label);
  }
  .arrow {
    font-size: 8px;
    margin-left: 4px;
  }
  .grip {
    position: absolute;
    top: 0;
    right: -3px;
    bottom: 0;
    width: 7px;
    cursor: col-resize;
    z-index: 1;
  }
  .tr {
    display: grid;
    align-items: center;
    min-height: 28px;
    content-visibility: auto;
    contain-intrinsic-size: auto 28px;
  }
  .tr.alt {
    background: var(--row-alt);
  }
  .tr.selected {
    background: var(--accent);
    color: #fff;
  }
  .td {
    padding: 4px 6px;
    min-width: 0;
    overflow: hidden;
    font-size: 12px;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .td.wrap {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
</style>
