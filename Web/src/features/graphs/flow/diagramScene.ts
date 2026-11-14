// The decisions `DataFlowDiagramView` makes around its layout: which layout runs (focus mode,
// butterfly, or layered), the lane offset of parallel edges, the focus reveal behind the ⊕
// badges, and the scale/offset that fit the graph into the frame. Pure functions, so they are
// tested without a DOM.
import type { Point, ViewTransform } from "../../../lib/diagram/geometry";
import { butterfly, layered, NODE_HEIGHT, NODE_WIDTH, type LayoutDirection, type LayoutEdge, type LayoutResult } from "./graphLayout";

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface DiagramLayoutInput {
  names: readonly string[];
  callEdges: readonly LayoutEdge[];
  dataEdges: readonly LayoutEdge[];
  direction: LayoutDirection;
  sourceNodes: readonly string[];
  centerNode: string | null;
  /** Focus mode: only these nodes are drawn; null draws the whole graph. */
  focus: ReadonlySet<string> | null;
}

const LANE_SPACING = 6;
/** The ⊕ reveal badge: a 13 px disc in the top-right corner, 3 px in from the edges. */
const BADGE_SIZE = 13;
const BADGE_INSET = 3;

export function isVisible(name: string, focus: ReadonlySet<string> | null): boolean {
  return focus === null || focus.has(name);
}

/** `computeLayout()`: in focus mode the layout runs over the focused nodes only. */
export function layoutDiagram(input: DiagramLayoutInput): LayoutResult {
  const { names, callEdges, dataEdges, direction, sourceNodes, centerNode, focus } = input;
  if (focus !== null) {
    const visible = names.filter((n) => focus.has(n));
    const subEdges = [...callEdges, ...dataEdges].filter((e) => focus.has(e.from) && focus.has(e.to));
    if (centerNode !== null && focus.has(centerNode)) return butterfly(visible, subEdges, centerNode);
    return layered(visible, subEdges, direction, sourceNodes.filter((n) => focus.has(n)));
  }
  if (centerNode !== null) return butterfly(names, callEdges, centerNode);
  return layered(names, callEdges, direction, sourceNodes);
}

/** Key of a directed edge; call and data edges between the same pair never share a lane. */
export function edgeKey(from: string, to: string, isCall: boolean): string {
  return `${isCall ? "C" : "D"}\u0001${from}\u0001${to}`;
}

/**
 * `computeEdgeLanes()`: edges that run between the same two rows share a corridor. Each one
 * gets a vertical offset, centred on the corridor, so parallel edges read as separate spokes.
 */
export function computeEdgeLanes(
  positions: ReadonlyMap<string, Point>,
  callEdges: readonly LayoutEdge[],
  dataEdges: readonly LayoutEdge[],
  focus: ReadonlySet<string> | null,
): Map<string, number> {
  const corridors = new Map<string, { from: string; to: string; isCall: boolean }[]>();
  const register = (from: string, to: string, isCall: boolean): void => {
    if (!isVisible(from, focus) || !isVisible(to, focus)) return;
    const start = positions.get(from);
    const end = positions.get(to);
    if (!start || !end) return;
    const key = `${Math.round(start.y)}\u0001${Math.round(end.y)}`;
    const corridor = corridors.get(key);
    const entry = { from, to, isCall };
    if (corridor) corridor.push(entry);
    else corridors.set(key, [entry]);
  };
  for (const e of callEdges) register(e.from, e.to, true);
  for (const e of dataEdges) register(e.from, e.to, false);

  const lanes = new Map<string, number>();
  for (const edges of corridors.values()) {
    const count = edges.length;
    edges.forEach((e, i) => {
      lanes.set(edgeKey(e.from, e.to, e.isCall), (i - (count - 1) / 2) * LANE_SPACING);
    });
  }
  return lanes;
}

/** True when `name` has a neighbour in the full graph that focus mode hides. */
export function hasHiddenNeighbours(
  name: string,
  callEdges: readonly LayoutEdge[],
  dataEdges: readonly LayoutEdge[],
  focus: ReadonlySet<string> | null,
): boolean {
  if (focus === null) return false;
  return [...callEdges, ...dataEdges].some(
    (e) => (e.from === name && !focus.has(e.to)) || (e.to === name && !focus.has(e.from)),
  );
}

/** `reveal(_:)`: the focused set plus the hidden neighbours of `name`. */
export function revealNeighbours(
  name: string,
  callEdges: readonly LayoutEdge[],
  dataEdges: readonly LayoutEdge[],
  focus: ReadonlySet<string>,
): Set<string> {
  const next = new Set(focus);
  for (const e of [...callEdges, ...dataEdges]) {
    if (e.from === name && !focus.has(e.to)) next.add(e.to);
    if (e.to === name && !focus.has(e.from)) next.add(e.from);
  }
  return next;
}

/** A node's box on screen: layout position and fixed size, mapped through the view transform. */
export function nodeScreenRect(position: Point, transform: ViewTransform): Rect {
  return {
    x: position.x * transform.scale + transform.offsetX,
    y: position.y * transform.scale + transform.offsetY,
    width: NODE_WIDTH * transform.scale,
    height: NODE_HEIGHT * transform.scale,
  };
}

/** The ⊕ badge of a node on screen. Its size is not scaled with the graph. */
export function revealBadgeRect(node: Rect): Rect {
  return {
    x: node.x + node.width - BADGE_SIZE - BADGE_INSET,
    y: node.y + BADGE_INSET,
    width: BADGE_SIZE,
    height: BADGE_SIZE,
  };
}

export function containsPoint(rect: Rect, point: Point): boolean {
  return point.x >= rect.x && point.x <= rect.x + rect.width && point.y >= rect.y && point.y <= rect.y + rect.height;
}

/**
 * The area a fit covers. In focus mode the visible nodes decide it, otherwise the whole
 * layout. The origin is the top-left of the area in layout coordinates.
 */
export function fitArea(layout: LayoutResult, focus: ReadonlySet<string> | null): Rect {
  const visible = [...layout.positions.entries()].filter(([name]) => isVisible(name, focus));
  if (visible.length === 0) return { x: 0, y: 0, width: layout.size.width, height: layout.size.height };
  const xs = visible.map(([, p]) => p.x);
  const ys = visible.map(([, p]) => p.y);
  const minX = Math.min(...xs);
  const minY = Math.min(...ys);
  return {
    x: minX,
    y: minY,
    width: Math.max(Math.max(...xs) + NODE_WIDTH - minX, 1),
    height: Math.max(Math.max(...ys) + NODE_HEIGHT - minY, 1),
  };
}

export interface FitOptions {
  /** Room kept around the graph, in px. */
  pad: number;
  minScale: number;
  maxScale: number;
}

/**
 * `recenter()`: the scale that fits `area` into `view` (never above `maxScale`, never below
 * `minScale`), and the offset that centres it. The transform maps area point p to
 * `p * scale + offset`.
 */
export function fitTransform(area: Rect, view: { width: number; height: number }, options: FitOptions): ViewTransform {
  const contentWidth = Math.max(area.width, 1);
  const contentHeight = Math.max(area.height, 1);
  const scaleX = (view.width - options.pad) / contentWidth;
  const scaleY = (view.height - options.pad) / contentHeight;
  const scale = Math.max(options.minScale, Math.min(scaleX, scaleY, options.maxScale));
  return {
    scale,
    offsetX: (view.width - contentWidth * scale) / 2 - area.x * scale,
    offsetY: (view.height - contentHeight * scale) / 2 - area.y * scale,
  };
}
