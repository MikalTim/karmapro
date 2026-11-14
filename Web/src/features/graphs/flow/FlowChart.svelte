<script lang="ts">
  // The control-flow chart of `FlowChartView` (Sources/KarmaAppKit/graphs/FlowChartView.swift) as SVG:
  // one box per statement or condition, joined by arrows coloured by branch. The chart fits the
  // frame and can be panned and zoomed (⌘-scroll or pinch zooms, a drag on empty space pans). Its
  // boxes can be dragged, except the entry, exit and join boxes. Box sizes come from flowChartLayout.ts.
  import { measureText } from "../../../lib/diagram/measure";
  import type { Point, ViewTransform } from "../../../lib/diagram/geometry";
  import { panZoom, type PanZoomOptions } from "../../../lib/diagram/panZoom";
  import { chartNodeText, layoutFlowChart, type ChartLayout } from "./flowChartLayout";
  import type { FlowChartDTO, FlowNodeDTO } from "./flowModel";
  import { containsPoint, fitTransform, type Rect } from "./diagramScene";
  import { uiFont } from "./textFit";

  // 11 px medium: the label font of every chart box.
  const LABEL_FONT = uiFont(11, 500);
  const FIT_OPTIONS = { pad: 40, minScale: 0.15, maxScale: 2.5 };
  const MIN_SCALE = 0.15;
  const MAX_SCALE = 6;
  const TEXT_INSET = 6;
  const BOX_CORNER = 6;
  const LINE_STEP = 13;
  // `NSColor(calibratedRed: 0.20, green: 0.60, blue: 0.35)` and `(0.78, 0.30, 0.30)` as hex.
  const ENTRY_FILL = "#339959";
  const EXIT_FILL = "#c74d4d";
  const WHITE = "#ffffff";
  const BLACK = "#000000";

  let { chart }: { chart: FlowChartDTO } = $props();

  let width = $state(0);
  let height = $state(0);
  // A dragged box moves in one layout; a new chart drops the moves.
  let dragged = $state.raw<{ layout: ChartLayout; positions: Map<number, Point> } | null>(null);
  // A pan or zoom keeps the user's transform until the chart changes.
  let userView = $state.raw<{ layout: ChartLayout; transform: ViewTransform } | null>(null);

  interface BoxView {
    node: FlowNodeDTO;
    rect: Rect;
    fill: string;
    stroke: string | null;
    radius: number;
    oval: boolean;
    textColour: string;
    lines: string[];
    centred: boolean;
    textX: number;
    textY: number;
  }

  interface EdgeView {
    x1: number;
    y1: number;
    x2: number;
    y2: number;
    stroke: string;
    strokeWidth: number;
    label: string | null;
    labelX: number;
    labelY: number;
    labelColour: string;
  }

  const measureLabel = (text: string) => measureText(text, LABEL_FONT);
  const layout = $derived(layoutFlowChart(chart, measureLabel));
  const positions = $derived(dragged !== null && dragged.layout === layout ? dragged.positions : layout.positions);
  const fitted = $derived(
    width > 0 && height > 0
      ? fitTransform(
          { x: 0, y: 0, width: layout.contentSize.width, height: layout.contentSize.height },
          { width, height },
          FIT_OPTIONS,
        )
      : { scale: 1, offsetX: 0, offsetY: 0 },
  );
  const transform = $derived(userView !== null && userView.layout === layout ? userView.transform : fitted);

  // Exported for the panel's Center button: it drops the user's pan and zoom and refits the chart.
  export function center(): void {
    userView = null;
  }

  function boxRect(id: number): Rect | null {
    const position = positions.get(id);
    const size = layout.sizes.get(id);
    if (!position || !size) return null;
    return {
      x: position.x * transform.scale + transform.offsetX,
      y: position.y * transform.scale + transform.offsetY,
      width: size.width * transform.scale,
      height: size.height * transform.scale,
    };
  }

  function fillOf(node: FlowNodeDTO): string {
    switch (node.kind) {
      case "entry":
        return ENTRY_FILL;
      case "exit":
        return EXIT_FILL;
      case "decision":
        return "var(--accent)";
      case "switch":
        return "var(--system-orange)";
      case "join":
        return "var(--separator)";
      case "block":
        return "var(--window-bg)";
    }
  }

  function textColourOf(node: FlowNodeDTO): string {
    switch (node.kind) {
      case "entry":
      case "exit":
      case "decision":
        return WHITE;
      case "switch":
        return BLACK;
      case "block":
      case "join":
        return "var(--label)";
    }
  }

  function strokeOf(node: FlowNodeDTO): string | null {
    if (node.kind === "decision") return null;
    if (node.kind === "switch") return "var(--system-orange)";
    return "var(--separator)";
  }

  function buildBox(node: FlowNodeDTO, rect: Rect): BoxView {
    const textWidth = Math.max(0, rect.width - TEXT_INSET * 2);
    const textHeight = Math.max(0, rect.height - TEXT_INSET * 2);
    const plan = chartNodeText(node, textWidth, textHeight, measureLabel);
    const isEnd = node.kind === "entry" || node.kind === "exit";
    const textLeft = rect.x + TEXT_INSET;
    return {
      node,
      rect,
      fill: fillOf(node),
      stroke: strokeOf(node),
      radius: isEnd ? rect.height / 2 : BOX_CORNER,
      oval: node.kind === "join",
      textColour: textColourOf(node),
      lines: plan.lines,
      centred: plan.centred,
      textX: plan.centred ? textLeft + textWidth / 2 : textLeft,
      textY: rect.y + TEXT_INSET,
    };
  }

  const boxes = $derived.by((): BoxView[] => {
    const views: BoxView[] = [];
    for (const node of chart.nodes) {
      const rect = boxRect(node.id);
      if (rect) views.push(buildBox(node, rect));
    }
    return views;
  });

  function edgeColour(branch: string | undefined, isBack: boolean): string {
    if (isBack) return "var(--system-blue)";
    if (branch === "T") return "var(--system-green)";
    if (branch === "F") return "var(--system-red)";
    return "var(--secondary-label)";
  }

  const edges = $derived.by((): EdgeView[] => {
    const views: EdgeView[] = [];
    for (const edge of chart.edges) {
      const from = boxRect(edge.from);
      const to = boxRect(edge.to);
      if (!from || !to) continue;
      // Edges join the box centres. Back edges are straight lines too: the Swift curve has its
      // control points on the end points.
      const x1 = from.x + from.width / 2;
      const y1 = from.y + from.height / 2;
      const x2 = to.x + to.width / 2;
      const y2 = to.y + to.height / 2;
      const branchLabel = edge.branch === "T" || edge.branch === "F" ? edge.branch : null;
      views.push({
        x1,
        y1,
        x2,
        y2,
        stroke: edgeColour(edge.branch, edge.isBackEdge),
        strokeWidth: edge.isBackEdge ? 1.3 : 1,
        label: branchLabel,
        labelX: (x1 + x2) / 2 + 6,
        labelY: (y1 + y2) / 2,
        labelColour: edge.branch === "T" ? "var(--system-green)" : "var(--system-red)",
      });
    }
    return views;
  });

  // Hit area of a box: its rect grown by 4 px on every side, as `nodeAt(point:)` tests it.
  function nodeAt(point: Point): number | null {
    for (const box of boxes) {
      if (box.node.kind === "entry" || box.node.kind === "exit" || box.node.kind === "join") continue;
      const hit = { x: box.rect.x - 4, y: box.rect.y - 4, width: box.rect.width + 8, height: box.rect.height + 8 };
      if (containsPoint(hit, point)) return box.node.id;
    }
    return null;
  }

  // The pan and zoom action names nodes by string; the chart's node ids are numbers.
  const panOptions: PanZoomOptions = {
    transform: () => transform,
    setTransform: (next) => {
      userView = { layout, transform: next };
    },
    minScale: MIN_SCALE,
    maxScale: MAX_SCALE,
    nodeAt: (point) => {
      const id = nodeAt(point);
      return id === null ? null : String(id);
    },
    nodePosition: (name) => positions.get(Number(name)) ?? { x: 0, y: 0 },
    onNodeMove: (name, position) => {
      const next = new Map(positions);
      next.set(Number(name), position);
      dragged = { layout, positions: next };
    },
    // The chart has no click action.
    onNodeClick: () => undefined,
    onUserTransform: () => {
      userView = { layout, transform };
    },
  };
</script>

<div class="chart" bind:clientWidth={width} bind:clientHeight={height} use:panZoom={panOptions}>
  <svg {width} {height} aria-hidden="true">
    {#each edges as edge, index (index)}
      <line x1={edge.x1} y1={edge.y1} x2={edge.x2} y2={edge.y2} style:stroke={edge.stroke} stroke-width={edge.strokeWidth} />
      {#if edge.label}
        <text class="branch" x={edge.labelX} y={edge.labelY} style:fill={edge.labelColour}>{edge.label}</text>
      {/if}
    {/each}

    {#each boxes as box (box.node.id)}
      {#if box.oval}
        <ellipse
          cx={box.rect.x + box.rect.width / 2}
          cy={box.rect.y + box.rect.height / 2}
          rx={box.rect.width / 2}
          ry={box.rect.height / 2}
          style:fill={box.fill}
        />
      {:else}
        <rect
          x={box.rect.x}
          y={box.rect.y}
          width={box.rect.width}
          height={box.rect.height}
          rx={box.radius}
          style:fill={box.fill}
          style:stroke={box.stroke}
        />
      {/if}
      {#each box.lines as line, index (index)}
        <text
          class="label"
          class:centred={box.centred}
          x={box.textX}
          y={box.textY + index * LINE_STEP}
          style:fill={box.textColour}
        >
          {line}
        </text>
      {/each}
    {/each}
  </svg>
</div>

<style>
  .chart {
    position: relative;
    width: 100%;
    height: 100%;
    overflow: hidden;
    background: var(--control-bg);
    user-select: none;
  }
  svg {
    display: block;
  }
  .label {
    font: 500 11px var(--font-ui);
    dominant-baseline: hanging;
  }
  .label.centred {
    text-anchor: middle;
  }
  .branch {
    font: 700 10px var(--font-ui);
    dominant-baseline: hanging;
  }
</style>
