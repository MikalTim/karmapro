// The variable-flow diagram in screen coordinates: the drawing order and every
// shape of `VariableFlowDiagramView.draw`, plus its hit tests. Each element is
// placed with the same view transform the AppKit view applies, and text sizes
// follow the zoom (box text scales with the graph, flowchart text does not).
import { arrowheadPath, orthogonalPath, type Point, type ViewTransform } from "../../../lib/diagram/geometry";
import { type Measure, ellipsize, fitLine, lineHeight, type TraceFonts, wrapText } from "./text";
import { type CalloutBox, type CalloutTap, type FlowLayoutNode, type Rect, type VariableLayout, FLOW_FONT_SIZE, FLOW_NODE_WEIGHT, isDraggableFlowKind } from "./variableFlowLayout";

/** A stroked path. Colours are CSS values: a theme variable or a literal. */
export interface ScenePath {
  shape: "path";
  d: string;
  stroke: string;
  width: number;
}

/** A rounded rectangle with an optional fill and outline. */
export interface SceneBox {
  shape: "box";
  x: number;
  y: number;
  width: number;
  height: number;
  radius: number;
  fill?: string;
  fillOpacity?: number;
  stroke?: string;
  strokeOpacity?: number;
  strokeWidth?: number;
}

export interface SceneOval {
  shape: "oval";
  cx: number;
  cy: number;
  r: number;
  fill: string;
}

/** Text whose top edge (the hanging baseline) sits at `y`, like `NSString.draw(at:)` in a flipped view. */
export interface SceneText {
  shape: "text";
  x: number;
  y: number;
  text: string;
  font: string;
  fill: string;
  anchor: "start" | "middle";
}

export type SceneItem = ScenePath | SceneBox | SceneOval | SceneText;

/** The positions the user has dragged things to; anything absent keeps its layout place. */
export interface SceneState {
  flowPositions: ReadonlyMap<number, Point>;
  /** Content-space offsets of callee boxes (and their use lines) moved by drag. */
  boxOffsets: ReadonlyMap<string, Point>;
}

const COLOR_ENTRY = "#339959";
const COLOR_EXIT = "#c74d4d";
const COLOR_HIGHLIGHT_TEXT = "#73610d";
const COLOR_LIGHT_TEXT = "#e6e6e6";
const COLOR_WHITE = "#ffffff";
const COLOR_BLACK = "#000000";
const CALLOUT_RADIUS = 8;
const FLOW_RADIUS = 6;
const FLOW_TEXT_INSET = 6;
const FLOW_CHART_SHAPE_INSET = 0.75;
const HIGHLIGHT_FILL_OPACITY = 0.22;
/** The zoom limits of `VariableFlowDiagramView` (`minScale`, `maxScale`). */
export const MIN_SCALE = 0.15;
export const MAX_SCALE = 6;

/** The view that fits a diagram of the given content size into the view (`recenter`). */
export function fitView(contentWidth: number, contentHeight: number, width: number, height: number): ViewTransform {
  const sW = Math.max(contentWidth, 300);
  const sH = Math.max(contentHeight, 200);
  const scale = Math.max(MIN_SCALE, Math.min((width - 40) / sW, (height - 40) / sH, 2));
  return {
    scale,
    offsetX: (width - sW * scale) / 2,
    offsetY: (height - sH * scale) / 2,
  };
}

export function viewRect(rect: Rect, transform: ViewTransform): Rect {
  return {
    x: rect.x * transform.scale + transform.offsetX,
    y: rect.y * transform.scale + transform.offsetY,
    width: rect.width * transform.scale,
    height: rect.height * transform.scale,
  };
}

function containsPoint(rect: Rect, point: Point, inset: number): boolean {
  return (
    point.x >= rect.x - inset &&
    point.x <= rect.x + rect.width + inset &&
    point.y >= rect.y - inset &&
    point.y <= rect.y + rect.height + inset
  );
}

function boxOffset(box: CalloutBox, state: SceneState): Point {
  return state.boxOffsets.get(box.id) ?? { x: 0, y: 0 };
}

/** A flowchart node's rectangle in content coordinates, at its current position. */
export function flowNodeContentRect(node: FlowLayoutNode, state: SceneState): Rect {
  const at = state.flowPositions.get(node.id) ?? { x: node.x, y: node.y };
  return { x: at.x, y: at.y, width: node.width, height: node.height };
}

/** A callee box's rectangle in content coordinates, at its current position. */
export function boxContentRect(box: CalloutBox, state: SceneState): Rect {
  const offset = boxOffset(box, state);
  return { ...box.rect, x: box.rect.x + offset.x, y: box.rect.y + offset.y };
}

/** A use line's rectangle in content coordinates: it moves with its box. */
export function tapContentRect(tap: CalloutTap, boxes: ReadonlyMap<string, CalloutBox>, state: SceneState): Rect {
  const box = boxes.get(tap.box);
  const offset = box ? boxOffset(box, state) : { x: 0, y: 0 };
  return { ...tap.rect, x: tap.rect.x + offset.x, y: tap.rect.y + offset.y };
}

/** The draggable flowchart statement under a screen point, if any (`flowAt`). */
export function flowNodeAt(point: Point, layout: VariableLayout, state: SceneState, transform: ViewTransform): number | null {
  for (const node of layout.flowNodes) {
    if (!isDraggableFlowKind(node.kind)) continue;
    if (containsPoint(viewRect(flowNodeContentRect(node, state), transform), point, 4)) return node.id;
  }
  return null;
}

/** The root callee box under a screen point, if any (`boxAt`). */
export function rootBoxAt(point: Point, layout: VariableLayout, state: SceneState, transform: ViewTransform): CalloutBox | null {
  for (const box of layout.boxes) {
    if (!box.root) continue;
    if (containsPoint(viewRect(boxContentRect(box, state), transform), point, 0)) return box;
  }
  return null;
}

/** The use line under a screen point (`mouseUp`'s tap check). */
export function tapAt(point: Point, layout: VariableLayout, state: SceneState, transform: ViewTransform): CalloutTap | null {
  const boxes = new Map(layout.boxes.map((box) => [box.id, box]));
  for (const tap of layout.taps) {
    if (containsPoint(viewRect(tapContentRect(tap, boxes, state), transform), point, 2)) return tap;
  }
  return null;
}

function flowFill(kind: FlowLayoutNode["kind"]): string {
  switch (kind) {
    case "entry":
      return COLOR_ENTRY;
    case "exit":
      return COLOR_EXIT;
    case "decision":
      return "var(--accent)";
    case "switch":
      return "var(--system-orange)";
    case "join":
      return "var(--separator)";
    default:
      return "var(--window-bg)";
  }
}

function flowOutline(node: FlowLayoutNode): { color: string; opacity: number } {
  const yellow = "var(--system-yellow)";
  switch (node.kind) {
    case "decision":
      return { color: node.highlighted ? yellow : "var(--accent)", opacity: 1 };
    case "switch":
      return { color: "var(--system-orange)", opacity: 1 };
    case "entry":
      return { color: COLOR_ENTRY, opacity: 0.6 };
    case "exit":
      return { color: COLOR_EXIT, opacity: 0.6 };
    default:
      return { color: node.highlighted ? yellow : "var(--separator)", opacity: 1 };
  }
}

function flowTextColor(node: FlowLayoutNode): string {
  switch (node.kind) {
    case "entry":
    case "exit":
    case "decision":
      return node.highlighted ? COLOR_LIGHT_TEXT : COLOR_WHITE;
    case "switch":
      return COLOR_BLACK;
    default:
      return node.highlighted ? COLOR_HIGHLIGHT_TEXT : "var(--label)";
  }
}

/** The shape of one flowchart statement, then its text (`drawFlowShape`). */
function flowNodeItems(node: FlowLayoutNode, rect: Rect, fonts: TraceFonts, measure: Measure): SceneItem[] {
  const items: SceneItem[] = [];
  const radius = node.kind === "entry" || node.kind === "exit" ? rect.height / 2 : FLOW_RADIUS;
  items.push({ shape: "box", ...rect, radius, fill: flowFill(node.kind) });
  if (node.highlighted) {
    items.push({
      shape: "box",
      ...rect,
      radius,
      fill: "var(--system-yellow)",
      fillOpacity: HIGHLIGHT_FILL_OPACITY,
    });
  }
  const outline = flowOutline(node);
  items.push({
    shape: "box",
    x: rect.x + FLOW_CHART_SHAPE_INSET,
    y: rect.y + FLOW_CHART_SHAPE_INSET,
    width: rect.width - FLOW_CHART_SHAPE_INSET * 2,
    height: rect.height - FLOW_CHART_SHAPE_INSET * 2,
    radius,
    stroke: outline.color,
    strokeOpacity: outline.opacity,
    strokeWidth: node.highlighted ? 3 : 1,
  });

  if (node.label === "") return items;
  const font = fonts.ui(FLOW_FONT_SIZE, FLOW_NODE_WEIGHT);
  const innerWidth = Math.max(0, rect.width - FLOW_TEXT_INSET * 2);
  const innerHeight = rect.height - FLOW_TEXT_INSET * 2;
  const step = lineHeight(FLOW_FONT_SIZE);
  const lines = wrapText(node.label, font, innerWidth, measure);
  const fits = Math.max(1, Math.floor(innerHeight / step + 0.01));
  const visible = lines.slice(0, fits);
  if (lines.length > fits) {
    visible[visible.length - 1] = ellipsize(visible[visible.length - 1] ?? "", font, innerWidth, measure);
  }
  visible.forEach((line, index) => {
    items.push({
      shape: "text",
      x: rect.x + rect.width / 2,
      y: rect.y + FLOW_TEXT_INSET + index * step,
      text: line,
      font,
      fill: flowTextColor(node),
      anchor: "middle",
    });
  });
  return items;
}

function edgeColor(isBackEdge: boolean, branch: string | null | undefined): string {
  if (isBackEdge) return "var(--system-blue)";
  if (branch === "T") return "var(--system-green)";
  if (branch === "F") return "var(--system-red)";
  return "var(--secondary-label)";
}

/** Every drawable of the diagram, back to front, in screen coordinates. */
export function buildVariableScene(
  layout: VariableLayout,
  state: SceneState,
  transform: ViewTransform,
  hasResult: boolean,
  fonts: TraceFonts,
  measure: Measure,
): SceneItem[] {
  if (!hasResult) {
    return [{ shape: "text", x: 20, y: 20, text: "No variable flow to display.", font: fonts.ui(13, 400), fill: "var(--secondary-label)", anchor: "start" }];
  }
  const items: SceneItem[] = [];
  const nodeRects = new Map<number, Rect>();
  for (const node of layout.flowNodes) {
    nodeRects.set(node.id, viewRect(flowNodeContentRect(node, state), transform));
  }
  const boxRects = new Map<string, Rect>();
  for (const box of layout.boxes) {
    boxRects.set(box.id, viewRect(boxContentRect(box, state), transform));
  }

  // Flowchart edges, with their T / F labels.
  for (const edge of layout.flowEdges) {
    const from = nodeRects.get(edge.from);
    const to = nodeRects.get(edge.to);
    if (!from || !to) continue;
    const start = { x: from.x + from.width / 2, y: from.y + from.height / 2 };
    const end = { x: to.x + to.width / 2, y: to.y + to.height / 2 };
    items.push({
      shape: "path",
      d: `M${start.x} ${start.y}L${end.x} ${end.y}`,
      stroke: edgeColor(edge.isBackEdge, edge.branch),
      width: edge.isBackEdge ? 1.3 : 1,
    });
    if (!edge.isBackEdge && (edge.branch === "T" || edge.branch === "F")) {
      items.push({
        shape: "text",
        x: (start.x + end.x) / 2 + 6,
        y: (start.y + end.y) / 2,
        text: edge.branch,
        font: fonts.ui(10, 700),
        fill: edge.branch === "T" ? "var(--system-green)" : "var(--system-red)",
        anchor: "start",
      });
    }
  }

  // Call arrows: down from the statement to the box, labelled "call".
  for (const edge of layout.callEdges) {
    const anchorRect = nodeRects.get(edge.anchor);
    const boxRect = boxRects.get(edge.box);
    if (!anchorRect || !boxRect) continue;
    const start = { x: anchorRect.x + anchorRect.width / 2, y: anchorRect.y + anchorRect.height };
    const end = { x: boxRect.x + boxRect.width / 2, y: boxRect.y };
    items.push({ shape: "path", d: orthogonalPath(start, end), stroke: "var(--system-blue)", width: 1.6 });
    items.push({ shape: "path", d: arrowheadPath(start, end, 9), stroke: "var(--label)", width: 2 });
    items.push({
      shape: "text",
      x: end.x - 26,
      y: (start.y + end.y) / 2 - 12,
      text: "call",
      font: fonts.ui(10, 700),
      fill: "var(--system-blue)",
      anchor: "start",
    });
  }

  // Return arrows: out of the box's left edge, round the channel, into the statement's right edge.
  for (const edge of layout.returnEdges) {
    const boxRect = boxRects.get(edge.box);
    const targetRect = nodeRects.get(edge.target);
    if (!boxRect || !targetRect) continue;
    const start = { x: boxRect.x, y: boxRect.y + boxRect.height / 2 };
    const end = { x: targetRect.x + targetRect.width, y: targetRect.y + targetRect.height / 2 };
    const channelX = Math.max(targetRect.x + targetRect.width + 26, boxRect.x - 40);
    items.push({
      shape: "path",
      d: `M${start.x} ${start.y}L${channelX} ${start.y}L${channelX} ${end.y}L${end.x} ${end.y}`,
      stroke: "var(--system-purple)",
      width: 1.6,
    });
    items.push({ shape: "path", d: arrowheadPath(end, start, 9), stroke: "var(--label)", width: 2 });
    items.push({
      shape: "text",
      x: channelX + 4,
      y: end.y - 6,
      text: "return",
      font: fonts.ui(10, 700),
      fill: "var(--system-purple)",
      anchor: "start",
    });
  }

  // Callee boxes: the frame first, then the flowchart statements over them.
  for (const box of layout.boxes) {
    const rect = boxRects.get(box.id);
    if (!rect || rect.width <= 0) continue;
    items.push({
      shape: "box",
      ...rect,
      radius: CALLOUT_RADIUS,
      fill: "var(--text-bg)",
      stroke: "var(--separator)",
      strokeOpacity: box.root ? 1 : 0.6,
      strokeWidth: 1.4,
    });
  }
  for (const node of layout.flowNodes) {
    const rect = nodeRects.get(node.id);
    if (!rect) continue;
    if (node.kind === "join") {
      items.push({ shape: "oval", cx: rect.x + rect.width / 2, cy: rect.y + rect.height / 2, r: rect.width / 2, fill: "var(--separator)" });
      continue;
    }
    items.push(...flowNodeItems(node, rect, fonts, measure));
  }
  for (const box of layout.boxes) {
    const rect = boxRects.get(box.id);
    if (!rect || rect.width <= 0) continue;
    items.push(...boxContentItems(box, rect, transform, fonts, measure));
  }
  return items;
}

/** The header, subtitle, use lines and collapse hint of one callee box, scaled with the view. */
function boxContentItems(box: CalloutBox, rect: Rect, transform: ViewTransform, fonts: TraceFonts, measure: Measure): SceneItem[] {
  const s = transform.scale;
  const items: SceneItem[] = [];
  const left = rect.x + 8;
  let y = rect.y + 8 * s;
  items.push({ shape: "text", x: left, y, text: box.header, font: fonts.ui(12 * s, 700), fill: "var(--label)", anchor: "start" });
  y += 18 * s;
  items.push({ shape: "text", x: left, y, text: box.subtitle, font: fonts.ui(9 * s, 400), fill: "var(--secondary-label)", anchor: "start" });
  y += (12 + 3) * s;

  const numberFont = fonts.mono(9 * s, 400);
  const codeFont = fonts.mono(10 * s, 400);
  const codeWidth = rect.width - 44 * s;
  for (const row of box.rows) {
    items.push({ shape: "text", x: left, y, text: `L${row.line}`, font: numberFont, fill: "var(--tertiary-label)", anchor: "start" });
    items.push({
      shape: "text",
      x: rect.x + 8 + 34 * s,
      y,
      text: fitLine(row.text, codeFont, codeWidth, measure),
      font: codeFont,
      fill: "var(--label)",
      anchor: "start",
    });
    y += 16 * s;
  }
  if (box.moreCount > 0) y += 16 * s;
  if (box.deeperCollapsed) {
    items.push({ shape: "text", x: left, y, text: "… deeper calls collapsed", font: fonts.ui(9 * s, 400), fill: "var(--secondary-label)", anchor: "start" });
  }
  return items;
}

