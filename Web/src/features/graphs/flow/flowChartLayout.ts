// Port of the layout and text decisions of `FlowChartView` (Sources/KarmaAppKit/graphs/FlowChartView.swift):
// the size of each node box from its label, the longest-path layering of the chart, and how a
// node's label is wrapped or truncated inside its box. Widths come from the injected `measure`.
import type { Point } from "../../../lib/diagram/geometry";
import type { FlowChartDTO, FlowEdgeDTO, FlowNodeDTO } from "./flowModel";
import type { LayoutSize } from "./graphLayout";
import { truncateTail, wrapLines, type Measure } from "./textFit";

/** Line height of the 11 px node label font. */
export const CHART_LINE_HEIGHT = 13;
const LABEL_MAX_WIDTH = 220;
const H_GAP = 40;
const V_GAP = 44;

export interface ChartLayout {
  positions: Map<number, Point>;
  sizes: Map<number, LayoutSize>;
  contentSize: LayoutSize;
}

/** The box of a node from its label: `nodeSize(_:)`. */
export function chartNodeSize(node: FlowNodeDTO, measure: Measure): LayoutSize {
  const lines = wrapLines(node.label, LABEL_MAX_WIDTH, measure);
  const textWidth = Math.max(0, ...lines.map((line) => measure(line)));
  const width = Math.ceil(textWidth) + 20;
  const height = Math.ceil(lines.length * CHART_LINE_HEIGHT) + 16;
  switch (node.kind) {
    case "decision":
      return { width: Math.max(width, 64), height: Math.max(height, 44) };
    case "switch":
    case "entry":
    case "exit":
      return { width: Math.max(width, 56), height: Math.max(height, 28) };
    case "join":
      return { width: 16, height: 16 };
    case "block":
      return { width: Math.max(width, 80), height: Math.max(height, 30) };
  }
}

/**
 * `computeLayout()`: each node's rank is the longest path to it over the forward edges (back
 * edges are ignored). Each rank is one row, centred, and the rows stack top to bottom.
 */
export function layoutFlowChart(chart: FlowChartDTO, measure: Measure): ChartLayout {
  const incoming = new Map<number, FlowEdgeDTO[]>();
  for (const e of chart.edges) {
    if (e.isBackEdge) continue;
    const list = incoming.get(e.to);
    if (list) list.push(e);
    else incoming.set(e.to, [e]);
  }

  const level = new Map<number, number>();
  const levelOf = (id: number): number => {
    const known = level.get(id);
    if (known !== undefined) return known;
    // A cycle without a back-edge flag would recurse forever; it counts as rank 0 while open.
    level.set(id, 0);
    let l = 0;
    for (const e of incoming.get(id) ?? []) l = Math.max(l, levelOf(e.from) + 1);
    level.set(id, l);
    return l;
  };
  for (const node of chart.nodes) levelOf(node.id);

  const sizes = new Map<number, LayoutSize>(chart.nodes.map((node) => [node.id, chartNodeSize(node, measure)]));
  const layers = new Map<number, number[]>();
  for (const node of chart.nodes) {
    const rank = level.get(node.id) ?? 0;
    const list = layers.get(rank);
    if (list) list.push(node.id);
    else layers.set(rank, [node.id]);
  }
  for (const ids of layers.values()) ids.sort((a, b) => a - b);

  const rowWidths = new Map<number, number>();
  const rowHeights = new Map<number, number>();
  let maxRowWidth = 0;
  for (const [rank, ids] of layers) {
    let width = 0;
    let height = 0;
    for (const id of ids) {
      const size = sizes.get(id) ?? { width: 0, height: 0 };
      if (width > 0) width += H_GAP;
      width += size.width;
      height = Math.max(height, size.height);
    }
    rowWidths.set(rank, width);
    rowHeights.set(rank, height);
    maxRowWidth = Math.max(maxRowWidth, width);
  }

  const positions = new Map<number, Point>();
  const maxLevel = Math.max(0, ...level.values());
  let yAccum = 0;
  for (let rank = 0; rank <= maxLevel; rank++) {
    const ids = layers.get(rank) ?? [];
    if (ids.length === 0) continue;
    let x = (maxRowWidth - (rowWidths.get(rank) ?? 0)) / 2;
    for (const id of ids) {
      positions.set(id, { x, y: yAccum });
      x += (sizes.get(id)?.width ?? 0) + H_GAP;
    }
    yAccum += (rowHeights.get(rank) ?? 30) + V_GAP;
  }

  return { positions, sizes, contentSize: { width: maxRowWidth, height: yAccum + 10 } };
}

/** How a node's label is drawn inside its text box. */
export interface NodeTextPlan {
  lines: string[];
  /** Entry, exit and switch labels are one centred line; the others are wrapped to the left. */
  centred: boolean;
}

/**
 * The lines drawn in a node's text box of `width` x `height` (already inset from the box). A
 * line that does not fit the height is not drawn, as `draw(in:)` does not draw it.
 */
export function chartNodeText(node: FlowNodeDTO, width: number, height: number, measure: Measure): NodeTextPlan {
  if (node.kind === "join") return { lines: [], centred: false };
  if (node.kind === "entry" || node.kind === "exit" || node.kind === "switch") {
    const line = truncateTail(node.label, width, measure);
    return { lines: line === "" ? [] : [line], centred: true };
  }
  const wrapped = wrapLines(node.label, width, measure);
  const visible = Math.min(wrapped.length, Math.floor(height / CHART_LINE_HEIGHT));
  return { lines: wrapped.slice(0, visible), centred: false };
}
