import { describe, expect, it } from "vitest";
import { butterfly, layered, type LayoutEdge } from "./graphLayout";

const edge = (from: string, to: string): LayoutEdge => ({ from, to });

describe("layered", () => {
  it("ranks a chain from its sink, so the caller sits on the bottom-most rank", () => {
    // a -> b -> c: c has rank 0 (top row), a has rank 2.
    const result = layered(["a", "b", "c"], [edge("a", "b"), edge("b", "c")], "leftToRight", []);
    expect(result.positions.get("c")).toEqual({ x: 0, y: 0 });
    expect(result.positions.get("b")).toEqual({ x: 0, y: 90 });
    expect(result.positions.get("a")).toEqual({ x: 0, y: 180 });
    expect(result.layerCount).toBe(3);
    // Width is the 400 minimum; height is 2 ranks of 90 plus one node height and 40.
    expect(result.size).toEqual({ width: 400, height: 254 });
  });

  it("ranks from the source nodes when laid out top to bottom", () => {
    const result = layered(["a", "b", "c"], [edge("a", "b"), edge("b", "c")], "topToBottom", ["a"]);
    expect(result.positions.get("a")?.y).toBe(0);
    expect(result.positions.get("b")?.y).toBe(90);
    expect(result.positions.get("c")?.y).toBe(180);
  });

  it("keeps the Swift x offsets of a row: the first node centre sits at half the row width", () => {
    // a -> b and a -> c: b and c share rank 0 (a row of two), a has rank 1 alone.
    const result = layered(["a", "b", "c"], [edge("a", "b"), edge("a", "c")], "leftToRight", []);
    expect(result.positions.get("b")).toEqual({ x: 86, y: 0 });
    expect(result.positions.get("c")).toEqual({ x: 258, y: 0 });
    expect(result.positions.get("a")).toEqual({ x: 0, y: 90 });
  });

  it("wraps a rank after nine nodes onto a second row", () => {
    const names = Array.from({ length: 10 }, (_, i) => `n${i}`);
    const result = layered(names, [], "leftToRight", []);
    // Nine nodes in the first row, the tenth alone below it at y = 34 + 18.
    expect(result.positions.get("n9")).toEqual({ x: 0, y: 52 });
    expect(result.size).toEqual({ width: 1504, height: 126 });
  });
});

describe("butterfly", () => {
  it("puts callers to the left, the centre in column 0 and callees to the right", () => {
    // a -> b, b -> c, b -> d: a is a caller; c and d are callees.
    const result = butterfly(["a", "b", "c", "d"], [edge("a", "b"), edge("b", "c"), edge("b", "d")], "b");
    expect(result.positions.get("b")).toEqual({ x: 22, y: 0 });
    expect(result.positions.get("a")).toEqual({ x: -150, y: 0 });
    expect(result.positions.get("c")).toEqual({ x: 194, y: 0 });
    expect(result.positions.get("d")).toEqual({ x: 194, y: 52 });
    expect(result.layerCount).toBe(3);
    // Columns span -150 to 322; the tallest column has two nodes.
    expect(result.size).toEqual({ width: 560, height: 144 });
  });

  it("falls back to the layered layout when the centre is not in the graph", () => {
    const edges = [edge("a", "b"), edge("b", "c")];
    expect(butterfly(["a", "b", "c"], edges, "missing")).toEqual(layered(["a", "b", "c"], edges, "leftToRight", []));
    expect(butterfly(["a", "b", "c"], edges, null)).toEqual(layered(["a", "b", "c"], edges, "leftToRight", []));
  });

  it("stacks functions unrelated to the centre in a block past the last callee column", () => {
    // a -> b, b -> c; x is unrelated and goes to column maxForward + 1 = 2.
    const result = butterfly(["a", "b", "c", "x"], [edge("a", "b"), edge("b", "c")], "b");
    expect(result.positions.get("x")).toEqual({ x: 2 * 172 + 22, y: 0 });
  });
});
