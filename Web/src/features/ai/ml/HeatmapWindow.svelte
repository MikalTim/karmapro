<script lang="ts">
  // The ML scan heatmap (`HeatmapWindowController`): one square per scanned file,
  // coloured cold to hot by its flagged-line count. A click opens the file at line 1.
  import { api } from "../../../lib/api";
  import { measureText } from "../../../lib/diagram/measure";
  import { on } from "../../../lib/events";
  import { showFileInMainWindow } from "../../main/navigation";
  import {
    CAPTION_FONT_FAMILY,
    CORNER_RADIUS,
    captionLayout,
    cellBox,
    columnCount,
    contentHeight,
    countTextColor,
    heatColor,
  } from "./heatmapGeometry";
  import { messageOf, type HeatmapDTO } from "./mlModel";

  let { windowId: _windowId }: { windowId: number } = $props();

  let heat = $state<HeatmapDTO | null>(null);
  let failure = $state("");
  let width = $state(0);

  const cells = $derived(heat?.cells ?? []);
  const columns = $derived(columnCount(width));
  const height = $derived(contentHeight(cells.length, width));
  const summary = $derived(failure || heat?.summary || "No scan results yet.");
  const laid = $derived(
    cells.map((cell, index) => {
      const box = cellBox(index, columns);
      return {
        cell,
        box,
        caption: captionLayout(cell.name, (text, fontPx) => measureText(text, `${fontPx}px ${CAPTION_FONT_FAMILY}`)),
        fill: heatColor(cell.intensity),
        count: countTextColor(cell.intensity),
      };
    }),
  );

  async function load() {
    try {
      heat = await api<HeatmapDTO>("GET", "/api/ml/heatmap");
      failure = "";
    } catch (error) {
      failure = messageOf(error);
    }
  }

  $effect(() => {
    void load();
    return on("ml.changed", () => void load());
  });
</script>

<div class="heatmap">
  <div class="header">
    <span class="summary">{summary}</span>
    <button class="btn" onclick={() => void load()}>Refresh</button>
  </div>
  <div class="scroll" bind:clientWidth={width}>
    <svg {width} {height} role="img" aria-label="ML scan heatmap">
      {#if cells.length === 0}
        <text class="empty" x="20" y="20">No scan results. Run an ML Project Scan first.</text>
      {/if}
      {#each laid as item (item.cell.path)}
        <g
          class="cell"
          role="button"
          tabindex="0"
          onclick={() => showFileInMainWindow(item.cell.path, 1)}
          onkeydown={(event) => event.key === "Enter" && showFileInMainWindow(item.cell.path, 1)}
        >
          <rect x={item.box.x} y={item.box.y} width={item.box.size} height={item.box.size} rx={CORNER_RADIUS} fill={item.fill} />
          <text
            class="count"
            x={item.box.x + item.box.size / 2}
            y={item.box.y + item.box.size / 2}
            fill={item.count}>{item.cell.flagged}</text
          >
        </g>
        <text class="caption" x={item.box.x} y={item.box.captionY} font-size={item.caption.fontPx}>{item.caption.text}</text>
      {/each}
    </svg>
  </div>
  <div class="legend">
    <div
      class="bar"
      style="background: linear-gradient(to right, {heatColor(0)}, {heatColor(0.5)}, {heatColor(1)})"
    ></div>
    <div class="labels">
      <span>Cold (fewer flagged lines)</span>
      <span>Hot (most flagged lines)</span>
    </div>
  </div>
</div>

<style>
  .heatmap {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }
  .header {
    flex: none;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 12px 16px 0;
  }
  .summary {
    flex: 1;
    min-width: 0;
    font-size: 12px;
    color: var(--secondary-label);
  }
  .scroll {
    flex: 1;
    min-height: 0;
    margin-top: 8px;
    overflow-y: auto;
  }
  svg {
    display: block;
  }
  .cell {
    cursor: pointer;
  }
  .cell:focus {
    outline: none;
  }
  .cell:focus-visible rect {
    stroke: var(--accent);
    stroke-width: 2px;
  }
  .count {
    font-size: 14px;
    font-weight: 700;
    text-anchor: middle;
    dominant-baseline: central;
  }
  .caption {
    fill: var(--label);
    dominant-baseline: hanging;
  }
  .empty {
    fill: var(--secondary-label);
    font-size: 14px;
    dominant-baseline: hanging;
  }
  .legend {
    flex: none;
    position: relative;
    height: 46px;
    margin: 8px 16px 12px;
  }
  .bar {
    position: absolute;
    left: 0;
    right: 0;
    top: 8px;
    height: 16px;
  }
  .labels {
    position: absolute;
    left: 0;
    right: 0;
    top: 28px;
    display: flex;
    justify-content: space-between;
    font-size: 11px;
    color: var(--secondary-label);
  }
</style>
