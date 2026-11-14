import { describe, expect, it } from "vitest";
import { butterfly, layered, type LayoutEdge } from "./graphLayout";
import {
  computeEdgeLanes,
  edgeKey,
  fitTransform,
  hasHiddenNeighbours,
  layoutDiagram,
  revealBadgeRect,
  revealNeighbours,
} from "./diagramScene";

const edge = (from: string, to: string): LayoutEdge => ({ from, to });

describe("layoutDiagram", () => {
  it("lays out the whole graph when focus mode is off", () => {
    const edges = [edge("a", "b"), edge("b", "c")];
    const result = layoutDiagram({
      names: ["a", "b", "c"],
      callEdges: edges,
      dataEdges: [],
      direction: "leftToRight",
      sourceNodes: [],
      centerNode: null,
      focus: null,
    });
    expect(result).toEqual(layered(["a", "b", "c"], edges, "leftToRight", []));
  });

  it("lays out only the focused nodes, with the edges between them", () => {
    const result = layoutDiagram({
      names: ["a", "b", "c"],
      callEdges: [edge("a", "b")],
      dataEdges: [edge("b", "c")],
      direction: "leftToRight",
      sourceNodes: [],
      centerNode: null,
      focus: new Set(["a", "b"]),
    });
    expect([...result.positions.keys()].sort()).toEqual(["a", "b"]);
    expect(result.positions.get("b")).toEqual({ x: 0, y: 0 });
  });

  it("uses the butterfly layout around the centre when the centre is focused", () => {
    const edges = [edge("a", "b"), edge("b", "c")];
    const result = layoutDiagram({
      names: ["a", "b", "c"],
      callEdges: edges,
      dataEdges: [],
      direction: "leftToRight",
      sourceNodes: [],
      centerNode: "b",
      focus: new Set(["a", "b", "c"]),
    });
    expect(result).toEqual(butterfly(["a", "b", "c"], edges, "b"));
  });
});

describe("computeEdgeLanes", () => {
  it("centres the lanes of edges that share a corridor", () => {
    // a sits on row 90; b and c sit on row 0, so both calls share one corridor.
    const positions = new Map([
      ["a", { x: 0, y: 90 }],
      ["b", { x: 86, y: 0 }],
      ["c", { x: 258, y: 0 }],
    ]);
    const lanes = computeEdgeLanes(positions, [edge("a", "b"), edge("a", "c")], [], null);
    expect(lanes.get(edgeKey("a", "b", true))).toBe(-3);
    expect(lanes.get(edgeKey("a", "c", true))).toBe(3);
  });

  it("keeps a call and a data edge between the same pair on separate lanes", () => {
    const positions = new Map([
      ["a", { x: 0, y: 90 }],
      ["b", { x: 0, y: 0 }],
    ]);
    const lanes = computeEdgeLanes(positions, [edge("a", "b")], [edge("a", "b")], null);
    expect(lanes.get(edgeKey("a", "b", true))).toBe(-3);
    expect(lanes.get(edgeKey("a", "b", false))).toBe(3);
  });
});

describe("focus reveal", () => {
  const calls = [edge("a", "b"), edge("b", "c")];
  const data: LayoutEdge[] = [];

  it("reports a focused node with a hidden neighbour", () => {
    expect(hasHiddenNeighbours("b", calls, data, new Set(["b"]))).toBe(true);
    expect(hasHiddenNeighbours("b", calls, data, new Set(["a", "b", "c"]))).toBe(false);
    expect(hasHiddenNeighbours("b", calls, data, null)).toBe(false);
  });

  it("adds every hidden neighbour of the clicked node to the focus", () => {
    expect([...revealNeighbours("b", calls, data, new Set(["b"]))].sort()).toEqual(["a", "b", "c"]);
  });

  it("places the ⊕ badge 3 px in from the top-right corner of the node", () => {
    expect(revealBadgeRect({ x: 100, y: 50, width: 128, height: 34 })).toEqual({ x: 212, y: 53, width: 13, height: 13 });
  });
});

describe("fitTransform", () => {
  it("scales the area to fit the view with the pad, then centres it", () => {
    // Content 100 x 50 at (10, 20) in a 200 x 150 view with a 40 px pad: the width limits the
    // scale to (200 - 40) / 100 = 1.6, and the offset moves the area's corner to the centre.
    const transform = fitTransform({ x: 10, y: 20, width: 100, height: 50 }, { width: 200, height: 150 }, {
      pad: 40,
      minScale: 0.15,
      maxScale: 2.5,
    });
    expect(transform.scale).toBeCloseTo(1.6);
    expect(transform.offsetX).toBeCloseTo(4);
    expect(transform.offsetY).toBeCloseTo(3);
  });

  it("clamps the scale to the limits", () => {
    const options = { pad: 0, minScale: 0.4, maxScale: 3 };
    expect(fitTransform({ x: 0, y: 0, width: 10, height: 10 }, { width: 500, height: 500 }, options).scale).toBe(3);
    expect(fitTransform({ x: 0, y: 0, width: 10000, height: 10 }, { width: 500, height: 500 }, options).scale).toBe(0.4);
  });
});
