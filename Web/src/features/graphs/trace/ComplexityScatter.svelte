<script lang="ts">
  // The complexity scatter (`ComplexityScatterView`): one dot per function, in
  // source order across the plot, coloured green to red by its complexity. A
  // hover shows the function's line in the window; a click opens it.
  import type { Point } from "../../../lib/diagram/geometry";
  import { showFileInMainWindow } from "../../main/navigation";
  import type { ComplexityPointDTO } from "./dto";
  import {
    CLICK_TOLERANCE,
    DOT_RADIUS,
    HALO_RADIUS,
    HOVER_TOLERANCE,
    complexityColor,
    labelledPoints,
    maxComplexity,
    plotRect,
    pointIndexAt,
    pointPosition,
    yTicks,
  } from "./complexityModel";
  import { browserFonts } from "./text";

  let {
    points,
    placeholder,
    onHover,
  }: {
    points: ComplexityPointDTO[];
    placeholder: string;
    onHover: (point: ComplexityPointDTO | null) => void;
  } = $props();

  let element: HTMLDivElement | undefined = $state();
  let width = $state(0);
  let height = $state(0);
  let hovered: number | null = $state(null);

  const maxC = $derived(maxComplexity(points));
  const plot = $derived(plotRect(width, height));
  const positions = $derived<Point[]>(
    points.map((point, index) => pointPosition(index, points.length, point.complexity, maxC, plot)),
  );
  const labels = $derived(labelledPoints(positions, hovered));
  const ticks = $derived(yTicks(maxC).map((value) => ({ value, y: plot.top + plot.height - (value / maxC) * plot.height })));
  const tickFont = $derived(browserFonts.ui(10, 400));
  const dotFont = $derived(browserFonts.mono(9, 700));
  const placeholderFont = $derived(browserFonts.ui(13, 400));

  function localPoint(event: { clientX: number; clientY: number }): Point {
    const bounds = element?.getBoundingClientRect();
    return { x: event.clientX - (bounds?.left ?? 0), y: event.clientY - (bounds?.top ?? 0) };
  }

  function pointerMove(event: PointerEvent): void {
    const index = pointIndexAt(localPoint(event), positions, HOVER_TOLERANCE);
    if (index === hovered) return;
    hovered = index;
    onHover(index === null ? null : points[index]);
  }

  function pointerLeave(): void {
    hovered = null;
    onHover(null);
  }

  function pointerDown(event: PointerEvent): void {
    const index = pointIndexAt(localPoint(event), positions, CLICK_TOLERANCE);
    const point = index === null ? undefined : points[index];
    if (point) showFileInMainWindow(point.path, point.line);
  }
</script>

<div
  class="scatter"
  bind:this={element}
  bind:clientWidth={width}
  bind:clientHeight={height}
  onpointermove={pointerMove}
  onpointerleave={pointerLeave}
  onpointerdown={pointerDown}
  role="presentation"
>
  <svg {width} {height} aria-hidden="true">
    {#if points.length === 0}
      <text
        x={width / 2}
        y={height / 2 - 8}
        text-anchor="middle"
        dominant-baseline="hanging"
        style="font: {placeholderFont}; fill: var(--secondary-label)"
      >{placeholder}</text>
    {:else}
      <rect
        x={plot.left}
        y={plot.top}
        width={plot.width}
        height={plot.height}
        fill="none"
        style="stroke: var(--separator)"
        stroke-width="1"
      />
      {#each ticks as tick (tick.value)}
        <line x1={plot.left} y1={tick.y} x2={plot.left - 4} y2={tick.y} style="stroke: var(--secondary-label)" stroke-width="1" />
        <text x={4} y={tick.y - 6} dominant-baseline="hanging" style="font: {tickFont}; fill: var(--secondary-label)">{tick.value}</text>
      {/each}
      <text x={plot.left - 6} y={height - 32} dominant-baseline="hanging" style="font: {tickFont}; fill: var(--secondary-label)">1</text>
      <text x={plot.left + plot.width - 90} y={height - 32} dominant-baseline="hanging" style="font: {tickFont}; fill: var(--secondary-label)">source order →</text>
      <text x={plot.left + plot.width - 12} y={height - 32} dominant-baseline="hanging" style="font: {tickFont}; fill: var(--secondary-label)">{points.length}</text>
      {#each points as point, index (index)}
        {@const center = positions[index]}
        <circle cx={center.x} cy={center.y} r={DOT_RADIUS} style="fill: {complexityColor(point.complexity, maxC)}" />
        {#if index === hovered}
          <circle cx={center.x} cy={center.y} r={HALO_RADIUS} fill="none" style="stroke: var(--accent)" stroke-width="2" />
        {/if}
        {#if labels[index]}
          <text x={center.x} y={center.y - 5.5} text-anchor="middle" dominant-baseline="hanging" style="font: {dotFont}; fill: #ffffff">{point.complexity}</text>
        {/if}
      {/each}
    {/if}
  </svg>
</div>

<style>
  .scatter {
    position: relative;
    flex: 1;
    min-height: 0;
    background: var(--control-bg);
    overflow: hidden;
  }
  svg {
    position: absolute;
    inset: 0;
  }
</style>
