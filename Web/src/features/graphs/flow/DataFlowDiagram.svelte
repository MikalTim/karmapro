<script lang="ts">
  // The call and data-flow diagram of `DataFlowDiagramView` (Sources/KarmaAppKit/graphs/DataFlowDiagramView.swift)
  // as SVG: function boxes joined by orthogonal call arrows and animated dashed data arrows.
  // Layout, lanes, focus and fitting come from graphLayout.ts and diagramScene.ts. Pan and zoom
  // follow the AppKit view: a drag on empty space pans, ⌘-scroll or pinch zooms, and a drag on a
  // box moves that box. A press without movement on a box is a click.
  import { measureText } from "../../../lib/diagram/measure";
  import { arrowheadPath, orthogonalPath, pointOnLine, type Point, type ViewTransform } from "../../../lib/diagram/geometry";
  import { panZoom, type PanZoomOptions } from "../../../lib/diagram/panZoom";
  import type { DiagramFlowStyle, DiagramGraphDTO, GraphNodeDTO } from "./diagramModel";
  import type { LayoutResult } from "./graphLayout";
  import {
    computeEdgeLanes,
    containsPoint,
    edgeKey,
    fitArea,
    fitTransform,
    hasHiddenNeighbours,
    isVisible,
    layoutDiagram,
    nodeScreenRect,
    revealBadgeRect,
    revealNeighbours,
    type Rect,
  } from "./diagramScene";
  import { truncateTail, uiFont } from "./textFit";

  // `DataFlowDiagramView.flowStyle` defaults: the orange `[8, 6]` dash of the app's other diagrams.
  const DEFAULT_FLOW_STYLE: DiagramFlowStyle = { color: "var(--system-orange)", dashes: [8, 6], lineWidth: 2.5, phaseStep: 2 };
  // The AppKit timer ticks 30 times a second.
  const TICKS_PER_SECOND = 30;
  const MIN_SCALE = 0.4;
  const MAX_SCALE = 6;
  const FIT_OPTIONS = { pad: 48, minScale: 0.4, maxScale: 3 };
  const NAME_FONT = uiFont(10, 500);
  const NODE_CORNER = 6;
  const HALO_CORNER = 9;
  const ORIGIN_COLOURS: Record<string, string> = {
    red: "var(--system-red)",
    orange: "var(--system-orange)",
    yellow: "var(--system-yellow)",
    green: "var(--system-green)",
    blue: "var(--system-blue)",
    gray: "var(--system-gray)",
    purple: "var(--system-purple)",
    teal: "var(--system-teal)",
    pink: "var(--system-pink)",
    indigo: "var(--system-indigo)",
  };
  // `NSColor(calibratedRed: 0.25, green: 0.60, blue: 1.0, alpha: 0.85)` and `calibratedWhite: 0.78`.
  const HIGHLIGHT_FILL = "#4099ffd9";
  const GREYED_FILL = "#c7c7c7";
  const LEGEND_LINE_START = 14;
  const LEGEND_LINE_END = 40;
  const LEGEND_TEXT_X = 48;

  let { graph, flowStyle = DEFAULT_FLOW_STYLE, onNodeClick }: {
    graph: DiagramGraphDTO;
    flowStyle?: DiagramFlowStyle;
    onNodeClick?: (name: string) => void;
  } = $props();

  interface NodeView {
    node: GraphNodeDTO;
    rect: Rect;
    fill: string;
    stroke: string;
    strokeWidth: number;
    icon: string;
    iconColour: string;
    name: string;
    nameColour: string;
    outlined: boolean;
    badge: Rect | null;
  }

  interface EdgeView {
    key: string;
    isCall: boolean;
    highlighted: boolean;
    path: string;
    head: string;
  }

  let width = $state(0);
  let height = $state(0);
  // A reveal changes the focus of one graph; the next graph starts from its own `focusNodes`.
  let revealed = $state.raw<{ graph: DiagramGraphDTO; focus: Set<string> } | null>(null);
  // A dragged box moves in a layout; a new layout (reveal, new graph) drops the moves.
  let dragged = $state.raw<{ layout: LayoutResult; positions: Map<string, Point> } | null>(null);
  // A pan or zoom keeps the user's transform until the layout changes (`hasUserViewTransform`).
  let userView = $state.raw<{ layout: LayoutResult; transform: ViewTransform } | null>(null);

  const dashPeriod = $derived(flowStyle.dashes.reduce((sum, dash) => sum + dash, 0));
  const flowDuration = $derived(flowStyle.phaseStep > 0 ? dashPeriod / (flowStyle.phaseStep * TICKS_PER_SECOND) : 0);
  const dashArray = $derived(flowStyle.dashes.join(" "));

  const focus = $derived.by((): Set<string> | null => {
    if (revealed !== null && revealed.graph === graph) return revealed.focus;
    return graph.focusNodes ? new Set(graph.focusNodes) : null;
  });

  const layout = $derived(
    layoutDiagram({
      names: graph.nodes.map((node) => node.name),
      callEdges: graph.callEdges,
      dataEdges: graph.dataEdges,
      direction: graph.layoutDirection,
      sourceNodes: graph.layoutSourceNodes,
      centerNode: graph.layoutCenterNode ?? null,
      focus,
    }),
  );
  const lanes = $derived(computeEdgeLanes(layout.positions, graph.callEdges, graph.dataEdges, focus));
  const positions = $derived(dragged !== null && dragged.layout === layout ? dragged.positions : layout.positions);
  const fitted = $derived(
    width > 0 && height > 0
      ? fitTransform(fitArea(layout, focus), { width, height }, FIT_OPTIONS)
      : { scale: 1, offsetX: 0, offsetY: 0 },
  );
  const transform = $derived(userView !== null && userView.layout === layout ? userView.transform : fitted);

  const visibleNodes = $derived(graph.nodes.filter((node) => isVisible(node.name, focus) && positions.has(node.name)));

  const rectsByName = $derived.by(() => {
    const rects = new Map<string, Rect>();
    for (const node of visibleNodes) {
      const position = positions.get(node.name);
      if (position) rects.set(node.name, nodeScreenRect(position, transform));
    }
    return rects;
  });

  function originColour(node: GraphNodeDTO): string {
    return ORIGIN_COLOURS[node.originColor ?? ""] ?? "var(--accent)";
  }

  function buildNodeView(node: GraphNodeDTO, rect: Rect): NodeView {
    const highlighted = node.name === graph.highlight;
    const origin = node.isOrigin;
    const colour = originColour(node);

    let fill = "var(--window-bg)";
    if (highlighted) fill = HIGHLIGHT_FILL;
    else if (origin) fill = `color-mix(in srgb, ${colour} 8%, transparent)`;
    else if (node.isGreyed) fill = GREYED_FILL;

    let stroke = "var(--separator)";
    let strokeWidth = 1;
    if (highlighted) {
      stroke = "var(--accent)";
      strokeWidth = 2.5;
    } else if (origin) {
      stroke = colour;
      strokeWidth = 1.6;
    } else if (node.isGreyed) {
      stroke = "var(--system-gray)";
    }

    let iconColour = "var(--secondary-label)";
    if (node.isGreyed) iconColour = "#000000";
    else if (highlighted) iconColour = "#ffffff";
    else if (origin) iconColour = colour;

    const hidden = focus !== null && hasHiddenNeighbours(node.name, graph.callEdges, graph.dataEdges, focus);
    return {
      node,
      rect,
      fill,
      stroke,
      strokeWidth,
      icon: origin ? "\u25fc" : "\u0192",
      iconColour,
      name: truncateTail(node.name, Math.max(0, rect.width - 26), (text) => measureText(text, NAME_FONT)),
      nameColour: node.isGreyed ? "#000000" : "var(--label)",
      outlined: node.isOutlined,
      badge: hidden ? revealBadgeRect(rect) : null,
    };
  }

  const nodeViews = $derived.by((): NodeView[] => {
    const views: NodeView[] = [];
    for (const node of visibleNodes) {
      const rect = rectsByName.get(node.name);
      if (rect) views.push(buildNodeView(node, rect));
    }
    return views;
  });

  function edgeView(from: string, to: string, isCall: boolean): EdgeView | null {
    if (!isVisible(from, focus) || !isVisible(to, focus)) return null;
    const first = rectsByName.get(from);
    const second = rectsByName.get(to);
    if (!first || !second) return null;
    // Edges leave the bottom centre of the source box and enter the top centre of the target.
    const sourcePoint = { x: first.x + first.width / 2, y: first.y + first.height };
    const targetPoint = { x: second.x + second.width / 2, y: second.y };
    const start = pointOnLine(sourcePoint, targetPoint, 8);
    const end = pointOnLine(targetPoint, sourcePoint, 8);
    const key = edgeKey(from, to, isCall);
    const lane = (lanes.get(key) ?? 0) * transform.scale;
    return {
      key,
      isCall,
      highlighted: from === graph.highlight || to === graph.highlight,
      path: orthogonalPath(start, end, lane),
      head: arrowheadPath(start, end, 9),
    };
  }

  const edges = $derived.by((): EdgeView[] => {
    const views: EdgeView[] = [];
    // A repeated edge draws the same line twice; one copy keeps the keyed each block valid.
    const seen = new Set<string>();
    const add = (view: EdgeView | null): void => {
      if (view && !seen.has(view.key)) {
        seen.add(view.key);
        views.push(view);
      }
    };
    // Dashed data edges go under the solid call edges.
    for (const edge of graph.dataEdges) add(edgeView(edge.from, edge.to, false));
    if (graph.animatedOnlyEdges) return views;
    // A pair that is also a data edge is drawn only as the animated line.
    const dataPairs = new Set<string>();
    for (const edge of graph.dataEdges) {
      if (isVisible(edge.from, focus) && isVisible(edge.to, focus)) dataPairs.add(`${edge.from}\u0001${edge.to}`);
    }
    for (const edge of graph.callEdges) {
      if (!dataPairs.has(`${edge.from}\u0001${edge.to}`)) add(edgeView(edge.from, edge.to, true));
    }
    return views;
  });

  function nodeAt(point: Point): string | null {
    for (const view of nodeViews) {
      if (containsPoint(view.rect, point)) return view.node.name;
    }
    return null;
  }

  // The ⊕ badge reveals the hidden neighbours of its node; the press does not start a drag.
  function revealAt(point: Point): boolean {
    if (focus === null) return false;
    for (const view of nodeViews) {
      if (view.badge !== null && containsPoint(view.badge, point)) {
        revealed = { graph, focus: revealNeighbours(view.node.name, graph.callEdges, graph.dataEdges, focus) };
        return true;
      }
    }
    return false;
  }

  const panOptions: PanZoomOptions = {
    transform: () => transform,
    setTransform: (next) => {
      userView = { layout, transform: next };
    },
    minScale: MIN_SCALE,
    maxScale: MAX_SCALE,
    nodeAt,
    nodePosition: (name) => positions.get(name) ?? { x: 0, y: 0 },
    onNodeMove: (name, position) => {
      const next = new Map(positions);
      next.set(name, position);
      dragged = { layout, positions: next };
    },
    onNodeClick: (name) => onNodeClick?.(name),
    onUserTransform: () => {
      userView = { layout, transform };
    },
    onPress: revealAt,
  };
</script>

<div class="diagram" bind:clientWidth={width} bind:clientHeight={height} use:panZoom={panOptions}>
  <svg {width} {height} aria-hidden="true">
    {#each edges as edge (edge.key)}
      {#if edge.isCall}
        <path class="call" d={edge.path} style:stroke={edge.highlighted ? "var(--accent)" : "var(--secondary-label)"} />
        <path class="head" d={edge.head} style:stroke={edge.highlighted ? "var(--accent)" : "var(--secondary-label)"} />
      {:else}
        <path
          class="flow"
          class:animated={flowDuration > 0}
          d={edge.path}
          stroke-width={flowStyle.lineWidth}
          stroke-dasharray={dashArray}
          style:stroke={flowStyle.color}
          style:--flow-duration="{flowDuration}s"
          style:--flow-period="{dashPeriod}px"
        />
        <path class="head" d={edge.head} style:stroke={flowStyle.color} />
      {/if}
    {/each}

    {#each nodeViews as view (view.node.name)}
      <g class="node">
        <rect
          x={view.rect.x}
          y={view.rect.y}
          width={view.rect.width}
          height={view.rect.height}
          rx={view.node.isOrigin ? 0 : NODE_CORNER}
          style:fill={view.fill}
          style:stroke={view.stroke}
          stroke-width={view.strokeWidth}
        />
        <text class="icon" x={view.rect.x + 8} y={view.rect.y + view.rect.height / 2 - 6} style:fill={view.iconColour}>
          {view.icon}
        </text>
        <text class="name" x={view.rect.x + 23} y={view.rect.y + view.rect.height / 2 - 6} style:fill={view.nameColour}>
          {view.name}
        </text>
        {#if view.outlined}
          <rect
            class="halo"
            x={view.rect.x - 3}
            y={view.rect.y - 3}
            width={view.rect.width + 6}
            height={view.rect.height + 6}
            rx={HALO_CORNER}
          />
        {/if}
        {#if view.badge}
          <circle
            class="badge"
            cx={view.badge.x + view.badge.width / 2}
            cy={view.badge.y + view.badge.height / 2}
            r={view.badge.width / 2}
          />
          <text class="plus" x={view.badge.x + view.badge.width / 2} y={view.badge.y + view.badge.height / 2}>+</text>
        {/if}
      </g>
    {/each}

    <g class="legend">
      <line class="legend-call" x1={LEGEND_LINE_START} y1="14" x2={LEGEND_LINE_END} y2="14" />
      <text class="legend-text" x={LEGEND_TEXT_X} y="6">Function call</text>
      <line class="legend-data" x1={LEGEND_LINE_START} y1="38" x2={LEGEND_LINE_END} y2="38" />
      <text class="legend-text" x={LEGEND_TEXT_X} y="30">Data flow (animated)</text>
    </g>
  </svg>
</div>

<style>
  .diagram {
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
  path,
  line,
  rect,
  circle {
    fill: none;
  }
  .call {
    stroke-width: 1.5;
  }
  .head {
    stroke-width: 2;
  }
  .flow.animated {
    animation: flow-dash var(--flow-duration) linear infinite;
  }
  @keyframes flow-dash {
    to {
      stroke-dashoffset: calc(-1 * var(--flow-period));
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .flow.animated {
      animation: none;
    }
  }
  .halo {
    stroke: var(--system-orange);
    stroke-width: 2.5;
    fill: color-mix(in srgb, var(--system-orange) 14%, transparent);
  }
  .icon {
    font: 800 11px var(--font-ui);
    dominant-baseline: hanging;
  }
  .name {
    font: 500 10px var(--font-ui);
    dominant-baseline: hanging;
  }
  .badge {
    fill: var(--accent);
  }
  .plus {
    font: 700 11px var(--font-ui);
    fill: #ffffff;
    text-anchor: middle;
    dominant-baseline: central;
  }
  .legend-call {
    stroke: var(--secondary-label);
    stroke-width: 1.5;
  }
  .legend-data {
    stroke: var(--system-orange);
    stroke-width: 2.5;
    stroke-dasharray: 6 4;
  }
  .legend-text {
    font: 400 11px var(--font-ui);
    fill: var(--secondary-label);
    dominant-baseline: hanging;
  }
</style>
