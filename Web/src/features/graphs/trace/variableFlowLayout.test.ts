import { describe, expect, it } from "vitest";
import type { CalloutDTO, FlowChartDTO, VariableFlowDTO } from "./dto";
import { LM, continuationNode, layoutVariableFlow } from "./variableFlowLayout";

// Seven characters per letter keeps the sizes easy to reason about.
const measure = (text: string) => text.length * 7;
const font = "500 11px test";

const chart: FlowChartDTO = {
  nodes: [
    { id: 0, kind: "entry", label: "START", line: null, highlighted: false },
    { id: 1, kind: "block", label: "x = 1", line: 2, highlighted: false },
    { id: 2, kind: "decision", label: "x > 0", line: 3, highlighted: false },
    { id: 3, kind: "block", label: "f(x)", line: 4, highlighted: true },
    { id: 4, kind: "join", label: "", line: null, highlighted: false },
    { id: 5, kind: "block", label: "return x", line: 5, highlighted: false },
    { id: 6, kind: "exit", label: "END", line: null, highlighted: false },
  ],
  edges: [
    { from: 0, to: 1, branch: null, isBackEdge: false },
    { from: 1, to: 2, branch: null, isBackEdge: false },
    { from: 2, to: 3, branch: "T", isBackEdge: false },
    { from: 2, to: 4, branch: "F", isBackEdge: false },
    { from: 3, to: 4, branch: null, isBackEdge: false },
    { from: 4, to: 5, branch: null, isBackEdge: false },
    { from: 5, to: 6, branch: null, isBackEdge: false },
    { from: 5, to: 2, branch: null, isBackEdge: true },
  ],
};

function callout(callLine: number, functionName: string, uses: number, children: CalloutDTO[] = []): CalloutDTO {
  return {
    callLine,
    functionName,
    variableName: "x",
    path: "/p/a.c",
    fileHint: "a.c",
    useLines: Array.from({ length: uses }, (_, index) => ({ line: 40 + index, text: `\tuse ${index}` })),
    children,
  };
}

function flowDTO(overrides: Partial<VariableFlowDTO>): VariableFlowDTO {
  return {
    variableName: "x",
    startFunction: "main",
    windowTitle: "Variable Flow — x",
    title: "Flow of “x” in main",
    caption: "",
    warnings: [],
    nodes: [
      { id: "n0", functionName: "main", variableName: "x", path: "/p/a.c", fileHint: "a.c", depth: 0, uses: [{ line: 2, text: "x = 1" }], isStart: true },
    ],
    edges: [],
    callouts: [],
    chart,
    ...overrides,
  };
}

describe("continuationNode", () => {
  it("resumes at the node after the first join of a decision's branches", () => {
    expect(continuationNode(2, chart.nodes, chart.edges)).toBe(5);
  });

  it("resumes at the next forward successor of a plain statement", () => {
    expect(continuationNode(3, chart.nodes, chart.edges)).toBe(4);
    expect(continuationNode(6, chart.nodes, chart.edges)).toBeNull();
  });
});

describe("layoutVariableFlow", () => {
  it("lays flowchart statements out one row per layer, with joins and exits at their own rows", () => {
    const layout = layoutVariableFlow(flowDTO({}), measure, font);
    const byId = new Map(layout.flowNodes.map((node) => [node.id, node]));
    expect(byId.get(4)).toMatchObject({ width: 16, height: 16 });
    expect(byId.get(2)?.width).toBeGreaterThanOrEqual(64);
    expect(byId.get(2)?.height).toBeGreaterThanOrEqual(44);
    expect(byId.get(3)?.y).toBeGreaterThan(byId.get(2)?.y ?? Infinity);
    expect(byId.get(4)?.y).toBeGreaterThan(byId.get(3)?.y ?? Infinity);
  });

  it("anchors a call box beside the statement it calls and returns to the statement after the call", () => {
    const layout = layoutVariableFlow(flowDTO({ callouts: [callout(4, "f", 1)] }), measure, font);
    expect(layout.callEdges).toEqual([{ anchor: 3, box: "b1" }]);
    expect(layout.returnEdges).toEqual([{ box: "b1", target: 4 }]);
    const box = layout.boxes.find((candidate) => candidate.id === "b1");
    expect(box?.root).toBe(true);
    expect(box?.rect.x).toBeCloseTo(layout.flowNodes.reduce((widest, node) => Math.max(widest, node.x + node.width), 0) + LM.panelGap);
    expect(box?.rect.height).toBe(8 + 18 + 3 + 12 + 3 + 16 + 10);
    expect(box?.header).toBe("f (x)");
    expect(box?.subtitle).toBe("a.c — called from line 4");
  });

  it("returns from a decision to the node after its join", () => {
    const layout = layoutVariableFlow(flowDTO({ callouts: [callout(3, "g", 0)] }), measure, font);
    expect(layout.callEdges).toEqual([{ anchor: 2, box: "b1" }]);
    expect(layout.returnEdges).toEqual([{ box: "b1", target: 5 }]);
  });

  it("writes tabs in use lines as two spaces and counts the lines beyond the row limit", () => {
    const layout = layoutVariableFlow(flowDTO({ callouts: [callout(4, "f", LM.maxRows + 2)] }), measure, font);
    const box = layout.boxes[0];
    expect(box.rows).toHaveLength(LM.maxRows);
    expect(box.rows[0]).toEqual({ line: 40, text: "  use 0" });
    expect(box.moreCount).toBe(2);
    expect(layout.taps).toHaveLength(LM.maxRows);
  });

  it("nests child boxes inside their parent, indented, and stops nesting at the depth limit", () => {
    let deepest = callout(1, "leaf", 1);
    for (let depth = 0; depth < LM.maxNest + 1; depth++) deepest = callout(1, `level${depth}`, 1, [deepest]);
    const layout = layoutVariableFlow(flowDTO({ callouts: [deepest] }), measure, font);
    const root = layout.boxes.find((box) => box.root);
    const child = layout.boxes.find((box) => !box.root && box.rect.x === (root?.rect.x ?? 0) + LM.childIndent);
    expect(root).toBeDefined();
    expect(child?.rect.x).toBeCloseTo((root?.rect.x ?? 0) + LM.childIndent);
    expect(child?.rect.width).toBeCloseTo(LM.boxW - LM.childIndent * 2);
    expect(layout.boxes.some((box) => box.deeperCollapsed)).toBe(true);
  });

  it("falls back to the start box beside the callees when there is no flowchart", () => {
    const layout = layoutVariableFlow(flowDTO({ chart: null, callouts: [callout(9, "f", 1), callout(12, "g", 1)] }), measure, font);
    expect(layout.flowNodes).toEqual([]);
    expect(layout.callEdges).toEqual([]);
    const [start, first, second] = layout.boxes;
    expect(start.rect).toMatchObject({ x: 20, y: 20, width: LM.boxW });
    expect(start.header).toBe("main · x");
    expect(first.rect.x).toBe(20 + LM.boxW + LM.panelGap);
    expect(second.rect.y).toBe(first.rect.y + first.rect.height + 18);
    expect(layout.contentWidth).toBe(first.rect.x + LM.boxW + 30);
  });

  it("is empty when the trace found nothing", () => {
    const layout = layoutVariableFlow(flowDTO({ nodes: [], callouts: [] }), measure, font);
    expect(layout.boxes).toEqual([]);
    expect(layout.contentWidth).toBe(0);
  });
});
