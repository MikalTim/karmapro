<script lang="ts" module>
  export interface Column<R> {
    id: string;
    title: string;
    width?: number;
    minWidth?: number;
    /** Sort key sent to `onSort`. Columns without one are not sortable. */
    sortKey?: string;
    /** Alignment of the cell text. Headers are always left-aligned, as in AppKit. */
    align?: "left" | "right" | "center";
    /** Plain-text cell value. Ignored when a `cell` snippet is given. */
    value?: (row: R) => string;
    /** Extra CSS for the cell text (for example a colour). */
    style?: (row: R) => string | undefined;
    /**
     * In `autoHeight` mode the cell text wraps and grows the row. Set false for a column whose AppKit field
     * truncates instead.
     */
    wrap?: boolean;
  }
</script>

<script lang="ts" generics="Row">
  // NSTableView: header with sortable, resizable columns; one selected row;
  // click, double-click and context-menu callbacks; alternating row colours.
  //
  // Two layouts exist:
  //  - fixed height (default): every row is `rowHeight` high and absolutely positioned.
  //  - `autoHeight` (`usesAutomaticRowHeights`): rows are laid out in normal flow, their cells wrap, and a row
  //    grows to fit them but never below `rowHeight`. Above 500 rows both layouts render only a window of rows.
  //    Wrapping rows keep their real heights: ResizeObserver measures them, and spacers stand in for rows
  //    outside the window. Unseen rows use the minimum height until measured.
  //
  // `lastColumnFills` is `.lastColumnOnlyAutoresizingStyle`: the last column takes all the width the other
  // columns leave, and the others keep their widths.
  import { tick, untrack } from "svelte";
  import { SvelteMap } from "svelte/reactivity";
  import type { Snippet } from "svelte";
  import { isAlternateRow, lastColumnWidth, stripeBackground } from "./stripes";
  import { rowAtOffset, rowOffsets, visibleRowWindow } from "./virtualRows";

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
    autoHeight = false,
    lastColumnFills = false,
    showHeader = true,
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
    /** Alternating row colours (`usesAlternatingRowBackgroundColors`); on unless a table turns it off. */
    striped?: boolean;
    emptyText?: string;
    rowStyle?: (row: Row) => string | undefined;
    /** Rows grow with their wrapping cells (`usesAutomaticRowHeights`). */
    autoHeight?: boolean;
    /** The last column takes the remaining width (`.lastColumnOnlyAutoresizingStyle`). */
    lastColumnFills?: boolean;
    /** False for a table without a header view (`headerView = nil`). */
    showHeader?: boolean;
  } = $props();

  const VIRTUALIZE_ABOVE = 500;
  const OVERSCAN = 20;
  const DEFAULT_WIDTH = 100;
  const DEFAULT_MIN_WIDTH = 30;

  let widths = $state<Record<string, number>>({});
  let scroller: HTMLDivElement | undefined = $state();
  let scrollTop = $state(0);
  let scrollLeft = $state(0);
  let viewHeight = $state(400);
  let viewWidth = $state(0);

  /** The width a column has before any fill rule: the one the user dragged to, else its own. */
  function ownWidth(column: Column<Row>): number {
    return widths[column.id] ?? column.width ?? DEFAULT_WIDTH;
  }

  function columnWidth(column: Column<Row>): number {
    const dragged = widths[column.id];
    if (dragged !== undefined || !lastColumnFills || column !== columns[columns.length - 1]) return ownWidth(column);
    const others = columns.slice(0, -1).reduce((sum, c) => sum + ownWidth(c), 0);
    return lastColumnWidth(viewWidth, others, column.minWidth ?? DEFAULT_MIN_WIDTH, ownWidth(column));
  }

  interface Measurement {
    row: Row;
    layout: string;
    height: number;
  }
  interface ObservedRow {
    key: string;
    row: Row;
    layout: string;
    enabled: boolean;
  }

  const measurements = new SvelteMap<string, Measurement>();
  const observedRows = new Map<HTMLElement, ObservedRow>();
  let observer: ResizeObserver | undefined;
  const virtual = $derived(rows.length > VIRTUALIZE_ABOVE);
  const flow = $derived(autoHeight);
  const layout = $derived(`${rowHeight}:${columns.map(columnWidth).join(",")}`);
  const offsets = $derived(autoHeight && virtual ? rowOffsets(rows, (row) => {
    const measured = measurements.get(rowKey(row));
    return measured?.row === row && measured.layout === layout ? measured.height : rowHeight;
  }, rowHeight) : []);
  const window = $derived(autoHeight && virtual ? visibleRowWindow(offsets, scrollTop, viewHeight, OVERSCAN) : null);
  const first = $derived(window?.first ?? (virtual ? Math.max(0, Math.floor(scrollTop / rowHeight) - OVERSCAN) : 0));
  const last = $derived(window?.last ?? (
    virtual ? Math.min(rows.length, Math.ceil((scrollTop + viewHeight) / rowHeight) + OVERSCAN) : rows.length
  ));
  const visible = $derived(rows.slice(first, last));
  const totalWidth = $derived(columns.reduce((sum, c) => sum + columnWidth(c), 0));

  // Measurements follow row keys through sorting. Discard removed rows, but keep off-screen rows cached.
  $effect(() => {
    const keys = new Set(rows.map(rowKey));
    untrack(() => {
      for (const key of measurements.keys()) if (!keys.has(key)) measurements.delete(key);
    });
  });
  $effect(() => () => observer?.disconnect());

  function measureRows(entries: ResizeObserverEntry[]) {
    if (!scroller || !virtual || !autoHeight) return;
    const anchorIndex = rowAtOffset(offsets, scroller.scrollTop);
    const anchor = rows[anchorIndex];
    const anchorKey = anchor === undefined ? null : rowKey(anchor);
    const inset = scroller.scrollTop - offsets[anchorIndex];
    const atEnd = scroller.scrollTop > 0 && scroller.scrollTop + viewHeight >= scroller.scrollHeight - 1;
    let changed = false;
    for (const entry of entries) {
      if (!(entry.target instanceof HTMLElement)) continue;
      const observed = observedRows.get(entry.target);
      if (!observed?.enabled) continue;
      const height = Math.max(rowHeight, entry.target.getBoundingClientRect().height);
      const previous = measurements.get(observed.key);
      if (previous?.row === observed.row && previous.layout === observed.layout && previous.height === height) continue;
      measurements.set(observed.key, { row: observed.row, layout: observed.layout, height });
      changed = true;
    }
    if (!changed) return;
    // Growing an overscan row must not move the visible row. At the bottom, keep the final row reachable.
    void tick().then(() => {
      if (!scroller || !virtual || !autoHeight) return;
      const index = rows.findIndex((row) => rowKey(row) === anchorKey);
      if (atEnd) scroller.scrollTop = scroller.scrollHeight - viewHeight;
      else if (index >= 0) scroller.scrollTop = offsets[index] + inset;
      scrollTop = scroller.scrollTop;
    });
  }

  function measureRow(node: HTMLElement, initial: ObservedRow) {
    let current = initial;
    function observe() {
      if (!current.enabled) return;
      observedRows.set(node, current);
      observer ??= new ResizeObserver(measureRows);
      observer.observe(node);
    }
    observe();
    return {
      update(next: ObservedRow) {
        if (current.key === next.key && current.row === next.row && current.layout === next.layout && current.enabled === next.enabled) return;
        observer?.unobserve(node);
        observedRows.delete(node);
        current = next;
        observe();
      },
      destroy() {
        observer?.unobserve(node);
        observedRows.delete(node);
      },
    };
  }
  // The empty space under the rows keeps alternating, starting with the colour the next row would have.
  const filler = $derived(stripeBackground(rowHeight, isAlternateRow(rows.length)));

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
    const target = event.currentTarget;
    if (!(target instanceof HTMLElement)) return;
    target.setPointerCapture(event.pointerId);
    const move = (e: PointerEvent) => {
      widths[column.id] = Math.max(column.minWidth ?? DEFAULT_MIN_WIDTH, startWidth + e.clientX - startX);
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
    if (flow && !virtual) {
      void tick().then(() => scroller?.querySelector(`[data-index="${next}"]`)?.scrollIntoView({ block: "nearest" }));
      return;
    }
    const top = autoHeight ? offsets[next] : next * rowHeight;
    if (scroller) {
      if (top < scroller.scrollTop) scroller.scrollTop = top;
      else if (top + rowHeight > scroller.scrollTop + viewHeight - 24) scroller.scrollTop = top + rowHeight - viewHeight + 24;
    }
    if (autoHeight) void tick().then(() => scroller?.querySelector(`[data-index="${next}"]`)?.scrollIntoView({ block: "nearest" }));
  }
</script>

<div class="table" role="grid" tabindex="0" onkeydown={keydown}>
  {#if showHeader}
    <div class="header" style="min-width:{totalWidth}px; transform:translateX({-scrollLeft}px)">
      {#each columns as column (column.id)}
        <div
          class="th"
          class:sortable={!!column.sortKey}
          style="width:{columnWidth(column)}px"
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
  {/if}
  <div
    style:overflow-anchor={autoHeight && virtual ? "none" : "auto"}
    class="body"
    bind:this={scroller}
    bind:clientHeight={viewHeight}
    bind:clientWidth={viewWidth}
    onscroll={() => {
      if (scroller) {
        scrollTop = scroller.scrollTop;
        scrollLeft = scroller.scrollLeft;
      }
    }}
    oncontextmenu={(e) => {
      if (e.target === e.currentTarget) {
        e.preventDefault();
        onContextMenu?.(null, e);
      }
    }}
    onclick={(e) => e.target === e.currentTarget && select(null)}
    role="presentation"
  >
    <div class="rows" style={flow ? `min-width:${totalWidth}px` : `height:${rows.length * rowHeight}px; min-width:${totalWidth}px`}>
      {#if autoHeight && virtual}
        <div style="height:{offsets[first]}px" aria-hidden="true"></div>
      {/if}
      {#each visible as row, i (rowKey(row))}
        {@const index = first + i}
        <div
          class="tr"
          class:flow
          class:alt={striped && isAlternateRow(index)}
          class:selected={rowKey(row) === selectedKey}
          data-index={index}
          use:measureRow={{ key: rowKey(row), row, layout, enabled: autoHeight && virtual }}
          style="{flow ? `min-height:${rowHeight}px` : `top:${index * rowHeight}px; height:${rowHeight}px`}; {rowStyle?.(row) ?? ''}"
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
              class:wrap={flow && column.wrap !== false}
              style="width:{columnWidth(column)}px; text-align:{column.align ?? 'left'}; {column.style?.(row) ?? ''}; {rowKey(row) === selectedKey ? 'color:#fff' : ''}"
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
      {#if autoHeight && virtual}
        <div style="height:{offsets[rows.length] - offsets[last]}px" aria-hidden="true"></div>
      {/if}
    </div>
    {#if striped}
      <div class="filler" style="min-width:{totalWidth}px; background:{filler}"></div>
    {/if}
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
    text-align: left;
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
    min-width: 0;
    overflow: auto;
    position: relative;
    display: flex;
    flex-direction: column;
  }
  .rows {
    position: relative;
    flex: none;
  }
  .filler {
    flex: 1 1 0;
    min-height: 0;
    pointer-events: none;
  }
  .tr {
    position: absolute;
    left: 0;
    right: 0;
    display: flex;
    align-items: center;
    min-width: 100%;
  }
  .tr.flow {
    position: relative;
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
  /* Wrapping cells have the same 4 px top and bottom insets as AppKit's wrapping fields. */
  .td.wrap {
    white-space: normal;
    overflow-wrap: anywhere;
    overflow: visible;
    text-overflow: clip;
    padding: 4px 6px;
  }
  .empty {
    position: absolute;
    top: 8px;
    left: 0;
    right: 0;
    text-align: center;
  }
</style>
