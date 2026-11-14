<script lang="ts">
  // `BacktraceDiagramView` (Sources/KarmaAppKit/graphs/BacktraceDiagramView.swift) as SVG: the frames of a
  // pasted stacktrace as one row of boxes, joined by arrows. A frame whose file is not in the open
  // project is drawn red. The row shrinks to fit the frame and is never enlarged beyond 1:1.
  import { measureText } from "../../../lib/diagram/measure";
  import { arrowheadPath } from "../../../lib/diagram/geometry";
  import type { BacktraceFrameDTO } from "./backtraceModel";
  import { containsPoint, type Rect } from "./diagramScene";
  import { monoFont, truncateMiddle, truncateTail, uiFont } from "./textFit";

  const NODE_WIDTH = 196;
  const NODE_HEIGHT = 80;
  const LANE_WIDTH = 56;
  const PAD = 24;
  const NODE_CORNER = 9;
  const ARROW_LENGTH = 7;
  const NAME_FONT = uiFont(12, 600);
  const FILE_FONT = monoFont(11, 400);

  let { frames, onFrameClick }: {
    frames: BacktraceFrameDTO[];
    onFrameClick?: (frame: BacktraceFrameDTO) => void;
  } = $props();

  let width = $state(0);
  let height = $state(0);

  interface FrameView {
    frame: BacktraceFrameDTO;
    index: number;
    rect: Rect;
    unresolved: boolean;
    name: string;
    file: string;
    fileBaseline: number;
  }

  const combWidth = $derived(
    frames.length === 0 ? PAD * 2 + NODE_WIDTH : PAD * 2 + frames.length * NODE_WIDTH + (frames.length - 1) * LANE_WIDTH,
  );
  const scale = $derived(Math.max(0.1, Math.min(1, (width - 4) / Math.max(combWidth, 1))));
  const offsetX = $derived((width - combWidth * scale) / 2);
  const offsetY = $derived((height - NODE_HEIGHT * scale) / 2);

  const rects = $derived(
    frames.map((_, index): Rect => ({
      x: offsetX + PAD * scale + index * (NODE_WIDTH + LANE_WIDTH) * scale,
      y: offsetY,
      width: NODE_WIDTH * scale,
      height: NODE_HEIGHT * scale,
    })),
  );

  const views = $derived.by((): FrameView[] => {
    return frames.map((frame, index) => {
      const rect = rects[index];
      const textWidth = Math.max(0, rect.width - 24);
      return {
        frame,
        index,
        rect,
        unresolved: frame.path === undefined,
        name: truncateTail(frame.functionName === "" ? "(unknown)" : frame.functionName, textWidth, (text) =>
          measureText(text, NAME_FONT),
        ),
        file: truncateMiddle(
          `${frame.fileHint}:${frame.line}${frame.path === undefined ? "  (not found)" : ""}`,
          textWidth,
          (text) => measureText(text, FILE_FONT),
        ),
        fileBaseline: rect.y + rect.height / 2 + 4,
      };
    });
  });

  const arrows = $derived(
    rects.slice(1).map((next, index) => {
      const from = rects[index];
      const start = { x: from.x + from.width + 2, y: from.y + from.height / 2 };
      const end = { x: next.x - 2, y: next.y + next.height / 2 };
      return { key: index, path: `M${start.x} ${start.y}L${end.x} ${end.y}${arrowheadPath(start, end, ARROW_LENGTH)}` };
    }),
  );

  // The frame under a point, for a click that starts and ends on the same box.
  function frameAt(x: number, y: number): BacktraceFrameDTO | null {
    for (const view of views) {
      if (containsPoint(view.rect, { x, y })) return view.frame;
    }
    return null;
  }

  function clickFrame(event: MouseEvent): void {
    const box = event.currentTarget instanceof Element ? event.currentTarget.getBoundingClientRect() : null;
    if (!box) return;
    const frame = frameAt(event.clientX - box.left, event.clientY - box.top);
    if (frame && onFrameClick) onFrameClick(frame);
  }
</script>

<div class="diagram" bind:clientWidth={width} bind:clientHeight={height}>
  <svg {width} {height} role="presentation" onclick={clickFrame}>
    {#each arrows as arrow (arrow.key)}
      <path class="arrow" d={arrow.path} />
    {/each}

    {#each views as view (view.index)}
      <g class="frame" class:unresolved={view.unresolved}>
        <rect x={view.rect.x} y={view.rect.y} width={view.rect.width} height={view.rect.height} rx={NODE_CORNER} />
        <text class="name" x={view.rect.x + 12} y={view.rect.y + 10}>{view.name}</text>
        <text class="file" x={view.rect.x + 12} y={view.fileBaseline}>{view.file}</text>
      </g>
    {/each}

    {#if frames.length === 0}
      <text class="hint" x="20" y="20">Analyse a stacktrace to see its frames here.</text>
    {/if}
  </svg>
</div>

<style>
  .diagram {
    width: 100%;
    height: 100%;
    overflow: hidden;
    background: var(--control-bg);
  }
  svg {
    display: block;
  }
  .arrow {
    fill: none;
    stroke: var(--tertiary-label);
    stroke-width: 1.5;
  }
  .frame rect {
    fill: var(--window-bg);
    stroke: var(--accent);
    stroke-width: 1.2;
  }
  .frame.unresolved rect {
    fill: #d938291f;
    stroke: var(--system-red);
    stroke-width: 1.6;
  }
  .name {
    font: 600 12px var(--font-ui);
    fill: var(--label);
    dominant-baseline: hanging;
  }
  .file {
    font: 400 11px var(--font-mono);
    fill: var(--secondary-label);
    dominant-baseline: hanging;
  }
  .frame.unresolved .file {
    fill: var(--system-red);
  }
  .hint {
    font: 400 13px var(--font-ui);
    fill: var(--secondary-label);
    dominant-baseline: hanging;
  }
</style>
