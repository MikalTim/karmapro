<script lang="ts" module>
  export interface Column<R> {
    id: string;
    title: string;
    width?: number;
    minWidth?: number;
    /** Sort key sent to `onSort`. Columns without one are not sortable. */
    sortKey?: string;
    align?: "left" | "right" | "center";
    /** Plain-text cell value. Ignored when a `cell` snippet is given. */
    value?: (row: R) => string;
    /** Extra CSS for the cell text (for example a colour). */
    style?: (row: R) => string | undefined;
  }
</script>

<script lang="ts" generics="Row">
  // NSTableView: header with sortable, resizable columns; one selected row;
  // click, double-click and context-menu callbacks; fixed row height. Long
  // lists (over 500 rows) render only the visible rows.
  import type { Snippet } from "svelte";

  let {
    columns,
    rows,
    rowKey,
    selectedKey = $bindable(null),
    rowHeight = 22,
    sortKey = null,
    ascending = true,
    onSort,
    onSelect,
    onDoubleClick,
    onContextMenu,
    cell,
    striped = true,
    emptyText,
    rowStyle,
  }: {
    columns: Column<Row>[];
    rows: Row[];
    rowKey: (row: Row) => string;
    selectedKey?: string | null;
    rowHeight?: number;
    sortKey?: string | null;
    ascending?: boolean;
    onSort?: (key: string, ascending: boolean) => void;
    onSelect?: (row: Row | null) => void;
    onDoubleClick?: (row: Row) => void;
    onContextMenu?: (row: Row | null, event: MouseEvent) => void;
    cell?: Snippet<[Row, Column<Row>]>;
    striped?: boolean;
    emptyText?: string;
    rowStyle?: (row: Row) => string | undefined;
  } = $props();

  const VIRTUALIZE_ABOVE = 500;
  const OVERSCAN = 20;

  let widths = $state<Record<string, number>>({});
  let scroller: HTMLDivElement | undefined = $state();
  let scrollTop = $state(0);
  let viewHeight = $state(400);

  function columnWidth(column: Column<Row>): number {
    return widths[column.id] ?? column.width ?? 100;
  }

  const virtual = $derived(rows.length > VIRTUALIZE_ABOVE);
  const first = $derived(virtual ? Math.max(0, Math.floor(scrollTop / rowHeight) - OVERSCAN) : 0);
  const last = $derived(
    virtual ? Math.min(rows.length, Math.ceil((scrollTop + viewHeight) / rowHeight) + OVERSCAN) : rows.length,
  );
  const visible = $derived(rows.slice(first, last));
  const totalWidth = $derived(columns.reduce((sum, c) => sum + columnWidth(c), 0));

  function headerClick(column: Column<Row>) {
    if (!column.sortKey || !onSort) return;
    // Like sortDescriptorsDidChange: a new column sorts ascending, the same one toggles.
    onSort(column.sortKey, sortKey === column.sortKey ? !ascending : true);
  }

  function select(row: Row | null) {
    selectedKey = row ? rowKey(row) : null;
    onSelect?.(row);
  }

  function startResize(column: Column<Row>, event: PointerEvent) {
    event.preventDefault();
    event.stopPropagation();
    const startX = event.clientX;
    const startWidth = columnWidth(column);
    const target = event.currentTarget as HTMLElement;
    target.setPointerCapture(event.pointerId);
    const move = (e: PointerEvent) => {
      widths[column.id] = Math.max(column.minWidth ?? 30, startWidth + e.clientX - startX);
    };
    const up = () => {
      target.removeEventListener("pointermove", move);
      target.removeEventListener("pointerup", up);
    };
    target.addEventListener("pointermove", move);
    target.addEventListener("pointerup", up);
  }

  function keydown(event: KeyboardEvent) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    event.preventDefault();
    const current = rows.findIndex((r) => rowKey(r) === selectedKey);
    const next = event.key === "ArrowDown" ? Math.min(rows.length - 1, current + 1) : Math.max(0, current - 1);
    if (next < 0 || next >= rows.length) return;
    select(rows[next]);
    const top = next * rowHeight;
    if (scroller) {
      if (top < scroller.scrollTop) scroller.scrollTop = top;
      else if (top + rowHeight > scroller.scrollTop + viewHeight - 24) scroller.scrollTop = top + rowHeight - viewHeight + 24;
    }
  }
</script>

<div class="table" role="grid" tabindex="0" onkeydown={keydown}>
  <div class="header" style="min-width:{totalWidth}px">
    {#each columns as column (column.id)}
      <div
        class="th"
        class:sortable={!!column.sortKey}
        style="width:{columnWidth(column)}px; text-align:{column.align ?? 'left'}"
        role="columnheader"
        tabindex="-1"
        onclick={() => headerClick(column)}
        onkeydown={(e) => e.key === "Enter" && headerClick(column)}
      >
        <span class="th-title">{column.title}</span>
        {#if column.sortKey && sortKey === column.sortKey}
          <span class="arrow">{ascending ? "▲" : "▼"}</span>
        {/if}
        <div class="grip" role="presentation" onpointerdown={(e) => startResize(column, e)} onclick={(e) => e.stopPropagation()}></div>
      </div>
    {/each}
  </div>
  <div
    class="body"
    bind:this={scroller}
    bind:clientHeight={viewHeight}
    onscroll={() => scroller && (scrollTop = scroller.scrollTop)}
    oncontextmenu={(e) => {
      if (e.target === e.currentTarget) {
        e.preventDefault();
        onContextMenu?.(null, e);
      }
    }}
    onclick={(e) => e.target === e.currentTarget && select(null)}
    role="presentation"
  >
    <div class="rows" style="height:{rows.length * rowHeight}px; min-width:{totalWidth}px">
      {#each visible as row, i (rowKey(row))}
        {@const index = first + i}
        <div
          class="tr"
          class:alt={striped && index % 2 === 1}
          class:selected={rowKey(row) === selectedKey}
          style="top:{index * rowHeight}px; height:{rowHeight}px; {rowStyle?.(row) ?? ''}"
          role="row"
          tabindex="-1"
          onclick={() => select(row)}
          ondblclick={() => onDoubleClick?.(row)}
          oncontextmenu={(e) => {
            e.preventDefault();
            select(row);
            onContextMenu?.(row, e);
          }}
          onkeydown={() => {}}
        >
          {#each columns as column (column.id)}
            <div
              class="td"
              style="width:{columnWidth(column)}px; text-align:{column.align ?? 'left'}; {column.style?.(row) ?? ''}"
              role="gridcell"
            >
              {#if cell}
                {@render cell(row, column)}
              {:else}
                {column.value?.(row) ?? ""}
              {/if}
            </div>
          {/each}
        </div>
      {/each}
    </div>
    {#if rows.length === 0 && emptyText}
      <div class="empty secondary">{emptyText}</div>
    {/if}
  </div>
</div>

<style>
  .table {
    display: flex;
    flex-direction: column;
    min-height: 0;
    min-width: 0;
    flex: 1;
    background: var(--control-bg);
    border: 1px solid rgba(255, 255, 255, 0.1);
    outline: none;
    overflow: hidden;
  }
  .header {
    display: flex;
    flex: none;
    background: #343436;
    border-bottom: 1px solid rgba(0, 0, 0, 0.5);
    overflow: hidden;
  }
  .th {
    position: relative;
    flex: none;
    height: 22px;
    line-height: 22px;
    padding: 0 6px;
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
  .body {
    flex: 1;
    min-height: 0;
    overflow: auto;
    position: relative;
  }
  .rows {
    position: relative;
  }
  .tr {
    position: absolute;
    left: 0;
    right: 0;
    display: flex;
    align-items: center;
    min-width: 100%;
  }
  .tr.alt {
    background: var(--row-alt);
  }
  .tr.selected {
    background: var(--accent);
    color: #fff;
  }
  .td {
    flex: none;
    padding: 0 6px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .empty {
    position: absolute;
    top: 8px;
    left: 0;
    right: 0;
    text-align: center;
  }
</style>
