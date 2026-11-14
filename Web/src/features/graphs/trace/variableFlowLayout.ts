// Layout of the variable-flow diagram in content coordinates, ported from
// `VariableFlowDiagramView.buildFlowArtwork`, `buildFallbackArtwork`, `sizeOf`
// and `placeBox`. The constants are the Swift `LM` metrics. Positions here are
// the start positions; the view moves them by drag.
import type { CalloutDTO, FlowChartDTO, FlowEdgeDTO, FlowNodeKind, LineTextDTO, VariableFlowDTO, VariableNodeDTO } from "./dto";
import { type Measure, lineHeight, wrapText } from "./text";

/** The `LM` layout metrics of `VariableFlowDiagramView`. */
export const LM = {
  hGap: 40,
  vGap: 44,
  boxW: 320,
  panelGap: 96,
  pad: 8,
  headerH: 18,
  subtitleH: 12,
  rowH: 16,
  maxRows: 10,
  childIndent: 14,
  maxNest: 4,
} as const;

export const FLOW_FONT_SIZE = 11;
const FLOW_TEXT_MAX_WIDTH = 220;

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface FlowLayoutNode {
  id: number;
  kind: FlowNodeKind;
  label: string;
  line: number | null;
  highlighted: boolean;
  width: number;
  height: number;
  /** Top-left corner in content coordinates. */
  x: number;
  y: number;
}

/** One callee box: the root boxes sit beside the flowchart, nested ones inside their parent. */
export interface CalloutBox {
  id: string;
  root: boolean;
  rect: Rect;
  header: string;
  subtitle: string;
  rows: LineTextDTO[];
  moreCount: number;
  deeperCollapsed: boolean;
}

/** A clickable use line inside a callee box; it moves with its box. */
export interface CalloutTap {
  box: string;
  rect: Rect;
  path: string;
  line: number;
}

/** A call arrow from a flowchart statement to the box it calls. */
export interface CallEdge {
  anchor: number;
  box: string;
}

/** A return arrow from a callee box back to the statement where execution resumes. */
export interface ReturnEdge {
  box: string;
  target: number;
}

export interface VariableLayout {
  flowNodes: FlowLayoutNode[];
  flowEdges: FlowEdgeDTO[];
  boxes: CalloutBox[];
  taps: CalloutTap[];
  callEdges: CallEdge[];
  returnEdges: ReturnEdge[];
  contentWidth: number;
  contentHeight: number;
}

export const EMPTY_LAYOUT: VariableLayout = {
  flowNodes: [],
  flowEdges: [],
  boxes: [],
  taps: [],
  callEdges: [],
  returnEdges: [],
  contentWidth: 0,
  contentHeight: 0,
};

/** The flowchart's own font: 11 pt medium, as `flowNodeSize` measures it. */
export const FLOW_NODE_WEIGHT = 500;

export function layoutVariableFlow(dto: VariableFlowDTO, measure: Measure, flowFont: string): VariableLayout {
  if (dto.nodes.length === 0) return EMPTY_LAYOUT;
  const sink = makeSink();
  if (dto.chart) return flowArtwork(dto, dto.chart, sink, measure, flowFont);
  const start = dto.nodes.find((node) => node.isStart) ?? dto.nodes[0];
  return fallbackArtwork(dto, start, sink);
}

/**
 * Where execution resumes after the statement at `anchor`: for a decision or
 * switch, the node after the first join its branches reach; otherwise the next
 * non-back-edge successor. `ControlFlowParser.continuationNode`.
 */
export function continuationNode(
  anchor: number,
  nodes: readonly { id: number; kind: FlowNodeKind }[],
  edges: readonly FlowEdgeDTO[],
): number | null {
  const kind = nodes.find((node) => node.id === anchor)?.kind;
  if (kind === undefined) return null;
  const outgoing = (id: number): number[] => edges.filter((edge) => edge.from === id && !edge.isBackEdge).map((edge) => edge.to);
  const first = outgoing(anchor)[0] ?? null;
  if (kind !== "decision" && kind !== "switch") return first;
  const seen = new Set<number>();
  const queue = outgoing(anchor);
  for (let index = 0; index < queue.length; index++) {
    const id = queue[index];
    if (seen.has(id)) continue;
    seen.add(id);
    if (nodes.find((node) => node.id === id)?.kind === "join") return outgoing(id)[0] ?? null;
    queue.push(...outgoing(id));
  }
  return first;
}

function flowNodeSize(kind: FlowNodeKind, label: string, measure: Measure, font: string): { width: number; height: number } {
  if (kind === "join") return { width: 16, height: 16 };
  const lines = wrapText(label, font, FLOW_TEXT_MAX_WIDTH, measure);
  const textWidth = lines.reduce((widest, line) => Math.max(widest, measure(line, font)), 0);
  const textHeight = lines.length * lineHeight(FLOW_FONT_SIZE);
  const width = Math.ceil(textWidth) + 20;
  const height = Math.ceil(textHeight) + 16;
  switch (kind) {
    case "decision":
      return { width: Math.max(width, 64), height: Math.max(height, 44) };
    case "switch":
    case "entry":
    case "exit":
      return { width: Math.max(width, 56), height: Math.max(height, 28) };
    default:
      return { width: Math.max(width, 80), height: Math.max(height, 30) };
  }
}

/** A statement the user can drag and click (`draggableKinds`). */
export function isDraggableFlowKind(kind: FlowNodeKind): boolean {
  return kind === "block" || kind === "decision" || kind === "switch";
}

interface BoxSink {
  boxes: CalloutBox[];
  taps: CalloutTap[];
  nextId(): string;
}

function makeSink(): BoxSink {
  let counter = 0;
  return {
    boxes: [],
    taps: [],
    nextId: () => {
      counter += 1;
      return `b${counter}`;
    },
  };
}

/** Height of one callee box, nested children included (`sizeOf`). */
function boxHeight(co: CalloutDTO, depth: number): number {
  let height = LM.pad + LM.headerH + 3 + LM.subtitleH + 3;
  height += Math.min(co.useLines.length, LM.maxRows) * LM.rowH;
  if (co.useLines.length > LM.maxRows) height += LM.rowH;
  if (co.children.length > 0) {
    height += 12;
    if (depth >= LM.maxNest) {
      height += 14;
    } else {
      for (const child of co.children) height += 8 + boxHeight(child, depth + 1);
    }
  }
  height += 10;
  return height;
}

/** Records a callee box at `rect`, its nested boxes and its clickable use lines (`placeBox`). */
function placeBox(sink: BoxSink, boxID: string, co: CalloutDTO, rect: Rect, depth: number): void {
  const header =
    co.callLine === 0
      ? co.variableName === ""
        ? co.functionName
        : `${co.functionName} · ${co.variableName}`
      : `${co.functionName} (${co.variableName})`;
  const subtitle = co.callLine === 0 ? co.fileHint : `${co.fileHint} — called from line ${co.callLine}`;
  const rows = co.useLines.slice(0, LM.maxRows).map((pair) => ({ line: pair.line, text: pair.text.split("\t").join("  ") }));
  const moreCount = Math.max(0, co.useLines.length - LM.maxRows);
  const deeperCollapsed = co.children.length > 0 && depth >= LM.maxNest;

  if (co.children.length > 0 && depth < LM.maxNest) {
    const childX = rect.x + LM.childIndent;
    const childWidth = rect.width - LM.childIndent * 2;
    let childY =
      rect.y +
      LM.pad +
      LM.headerH +
      3 +
      LM.subtitleH +
      3 +
      Math.min(co.useLines.length, LM.maxRows) * LM.rowH +
      (co.useLines.length > LM.maxRows ? LM.rowH : 0) +
      12;
    for (const child of co.children) {
      const height = boxHeight(child, depth + 1);
      placeBox(sink, sink.nextId(), child, { x: childX, y: childY, width: childWidth, height }, depth + 1);
      childY += height + 8;
    }
  }

  sink.boxes.push({ id: boxID, root: false, rect, header, subtitle, rows, moreCount, deeperCollapsed });
  let rowY = rect.y + LM.pad + LM.headerH + 3 + LM.subtitleH + 3;
  for (const row of rows) {
    sink.taps.push({
      box: boxID,
      rect: { x: rect.x + LM.pad - 2, y: rowY - 1, width: rect.width - LM.pad * 2 + 4, height: LM.rowH + 2 },
      path: co.path,
      line: row.line,
    });
    rowY += LM.rowH;
  }
}

function markRoots(boxes: CalloutBox[], rootIDs: readonly string[]): CalloutBox[] {
  const roots = new Set(rootIDs);
  return boxes.map((box) => (roots.has(box.id) ? { ...box, root: true } : box));
}

function flowArtwork(dto: VariableFlowDTO, chart: FlowChartDTO, sink: BoxSink, measure: Measure, flowFont: string): VariableLayout {
  const nodes: FlowLayoutNode[] = chart.nodes.map((node) => {
    const size = flowNodeSize(node.kind, node.label, measure, flowFont);
    return {
      id: node.id,
      kind: node.kind,
      label: node.label,
      line: node.line ?? null,
      highlighted: node.highlighted,
      width: size.width,
      height: size.height,
      x: 0,
      y: 0,
    };
  });
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const edges = chart.edges;

  // Longest-path layering over the forward edges (`levelOf`). A node is marked
  // before its predecessors are visited, so a malformed cycle cannot recurse forever.
  const level = new Map<number, number>();
  const levelOf = (id: number): number => {
    const known = level.get(id);
    if (known !== undefined) return known;
    level.set(id, 0);
    let value = 0;
    for (const edge of edges) {
      if (!edge.isBackEdge && edge.to === id) value = Math.max(value, levelOf(edge.from) + 1);
    }
    level.set(id, value);
    return value;
  };
  for (const node of nodes) levelOf(node.id);

  const layers = new Map<number, number[]>();
  for (const node of nodes) {
    const row = level.get(node.id) ?? 0;
    const ids = layers.get(row);
    if (ids) ids.push(node.id);
    else layers.set(row, [node.id]);
  }
  for (const ids of layers.values()) ids.sort((a, b) => a - b);
  const maxLevel = [...level.values()].reduce((highest, value) => Math.max(highest, value), 0);

  const rowWidths = new Map<number, number>();
  const rowHeights = new Map<number, number>();
  let maxRowWidth = 0;
  for (const [row, ids] of layers) {
    let width = 0;
    let height = 0;
    for (const id of ids) {
      const node = byId.get(id);
      if (!node) continue;
      if (width > 0) width += LM.hGap;
      width += node.width;
      height = Math.max(height, node.height);
    }
    rowWidths.set(row, width);
    rowHeights.set(row, height);
    maxRowWidth = Math.max(maxRowWidth, width);
  }

  let yAccum = 0;
  let flowMaxX = 0;
  for (let row = 0; row <= maxLevel; row++) {
    const ids = layers.get(row) ?? [];
    if (ids.length === 0) continue;
    let x = (maxRowWidth - (rowWidths.get(row) ?? 0)) / 2;
    for (const id of ids) {
      const node = byId.get(id);
      if (!node) continue;
      node.x = x;
      node.y = yAccum;
      x += node.width + LM.hGap;
      flowMaxX = Math.max(flowMaxX, x - LM.hGap);
    }
    yAccum += (rowHeights.get(row) ?? 30) + LM.vGap;
  }
  const flowMaxY = Math.max(yAccum - LM.vGap, 0);

  const callouts = dto.callouts;
  if (callouts.length === 0) {
    return {
      ...EMPTY_LAYOUT,
      flowNodes: nodes,
      flowEdges: edges,
      contentWidth: Math.max(flowMaxX, 200) + 30,
      contentHeight: Math.max(flowMaxY, 60) + 20,
    };
  }

  const flowNodeAtLine = (line: number): number | null =>
    nodes.find((node) => node.line === line && isDraggableFlowKind(node.kind))?.id ?? null;
  // The statement after `line` that the call returns to, or the END node.
  const returnTargetAfter = (line: number): number | null => {
    let best: FlowLayoutNode | undefined;
    for (const node of nodes) {
      if (!isDraggableFlowKind(node.kind) || (node.line ?? -1) <= line) continue;
      if (!best || (node.line ?? Number.MAX_SAFE_INTEGER) < (best.line ?? Number.MAX_SAFE_INTEGER)) best = node;
    }
    if (best) return best.id;
    return nodes.find((node) => node.kind === "exit")?.id ?? null;
  };

  // Callee boxes are placed in the order of the statements that call them.
  const anchored = callouts.map((co) => {
    const id = flowNodeAtLine(co.callLine);
    const node = id === null ? undefined : byId.get(id);
    return { order: node ? node.y : Number.MAX_VALUE, line: co.callLine, co };
  });
  anchored.sort((a, b) => {
    if (a.order !== b.order) return a.order < b.order ? -1 : 1;
    return a.line - b.line;
  });

  const panelX = flowMaxX + LM.panelGap;
  let prevBottom = -Number.MAX_VALUE;
  let maxBoxBottom = 0;
  const rootIDs: string[] = [];
  const callEdges: CallEdge[] = [];
  const returnEdges: ReturnEdge[] = [];
  for (const item of anchored) {
    const anchor = flowNodeAtLine(item.line);
    const height = boxHeight(item.co, 0);
    const node = anchor === null ? undefined : byId.get(anchor);
    const anchorCenterY = node ? node.y + node.height / 2 : 0;
    const y = Math.max(anchorCenterY - height / 2, prevBottom + 18);
    const rect: Rect = { x: panelX, y, width: LM.boxW, height };
    const boxID = sink.nextId();
    placeBox(sink, boxID, item.co, rect, 0);
    rootIDs.push(boxID);
    maxBoxBottom = Math.max(maxBoxBottom, rect.y + rect.height);
    prevBottom = rect.y + rect.height;
    if (anchor !== null) {
      callEdges.push({ anchor, box: boxID });
      const target = continuationNode(anchor, nodes, edges) ?? returnTargetAfter(item.line);
      if (target !== null) returnEdges.push({ box: boxID, target });
    }
  }

  return {
    flowNodes: nodes,
    flowEdges: edges,
    boxes: markRoots(sink.boxes, rootIDs),
    taps: sink.taps,
    callEdges,
    returnEdges,
    contentWidth: Math.max(flowMaxX, panelX + LM.boxW) + 30,
    contentHeight: Math.max(flowMaxY, maxBoxBottom) + 20,
  };
}

/** No flowchart: the start frame as a wide box on the left, its callees stacked to the right. */
function fallbackArtwork(dto: VariableFlowDTO, start: VariableNodeDTO, sink: BoxSink): VariableLayout {
  const startBox: CalloutDTO = {
    callLine: 0,
    functionName: dto.startFunction,
    variableName: dto.variableName,
    path: start.path,
    fileHint: start.fileHint,
    useLines: start.uses,
    children: [],
  };
  const rootRect: Rect = { x: 20, y: 20, width: LM.boxW, height: boxHeight(startBox, 0) };
  const rootID = sink.nextId();
  placeBox(sink, rootID, startBox, rootRect, 0);
  const rootIDs = [rootID];
  const rootRight = rootRect.x + rootRect.width;
  const rootBottom = rootRect.y + rootRect.height;

  if (dto.callouts.length === 0) {
    return {
      flowNodes: [],
      flowEdges: [],
      boxes: markRoots(sink.boxes, rootIDs),
      taps: sink.taps,
      callEdges: [],
      returnEdges: [],
      contentWidth: rootRight + 30,
      contentHeight: rootBottom + 30,
    };
  }

  const panelX = rootRight + LM.panelGap;
  let y = rootRect.y;
  let maxBottom = rootBottom;
  for (const child of dto.callouts) {
    const height = boxHeight(child, 0);
    const rect: Rect = { x: panelX, y, width: LM.boxW, height };
    const id = sink.nextId();
    placeBox(sink, id, child, rect, 0);
    rootIDs.push(id);
    maxBottom = Math.max(maxBottom, rect.y + height);
    y = rect.y + height + 18;
  }
  return {
    flowNodes: [],
    flowEdges: [],
    boxes: markRoots(sink.boxes, rootIDs),
    taps: sink.taps,
    callEdges: [],
    returnEdges: [],
    contentWidth: panelX + LM.boxW + 30,
    contentHeight: maxBottom + 20,
  };
}
