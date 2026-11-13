import { describe, expect, it } from "vitest";
import { arrowShapes, indentColumns, shapesToSvg } from "./flowArrows";

const anchor = (line: number) => (line <= 10 ? line * 16 + 10 : null);
const startX = (line: number) => 8 + (line % 2) * 8;

describe("arrowShapes", () => {
  it("draws a bow from the source line, along the kind's lane, to the target", () => {
    const [shape] = arrowShapes([{ fromLine: 2, toLine: 4, kind: "branchFalse" }], anchor, startX);
    // fromX = 8 - 2, toX = 8 - 2, lane = 2 + 2.
    expect(shape.stroke?.d).toBe("M6 42C4 42 4 74 6 74");
    expect(shape.stroke?.width).toBe(1.3);
    expect(shape.dot).toEqual({ cx: 6, cy: 42, r: 1.6 });
    expect(shape.head).toBe("7,74 2,71.4 2,76.6");
    expect(shape.color).toBe("var(--system-red)");
  });

  it("draws plain flow thinner and exit as a chevron with no start dot", () => {
    const [flow] = arrowShapes([{ fromLine: 1, toLine: 3, kind: "flow" }], anchor, startX);
    expect(flow.stroke?.width).toBe(1);
    const [exit] = arrowShapes([{ fromLine: 2, toLine: 2, kind: "exit" }], anchor, startX);
    expect(exit.dot).toBeNull();
    expect(exit.stroke?.d).toBe("M0 42L3 42");
    expect(exit.head).toBe("3,39.6 7,42 3,44.4");
  });

  it("skips arrows on the same row, off-layout lines and arrows outside the visible range", () => {
    expect(arrowShapes([{ fromLine: 2, toLine: 2, kind: "flow" }], anchor, startX)).toEqual([]);
    expect(arrowShapes([{ fromLine: 2, toLine: 40, kind: "flow" }], anchor, startX)).toEqual([]);
    const far = [{ fromLine: 9, toLine: 10, kind: "flow" as const }];
    expect(arrowShapes(far, anchor, startX, { top: 0, bottom: 50 })).toEqual([]);
    expect(arrowShapes(far, anchor, startX, { top: 0, bottom: 500 })).toHaveLength(1);
  });
});

describe("shapesToSvg", () => {
  it("emits a path, a dot and a head for a bow", () => {
    const svg = shapesToSvg(arrowShapes([{ fromLine: 1, toLine: 3, kind: "loopBack" }], anchor, startX));
    expect(svg).toContain("<path ");
    expect(svg).toContain("<circle ");
    expect(svg).toContain("<polygon ");
    expect(svg).toContain("var(--system-blue)");
  });
});

describe("indentColumns", () => {
  it("counts spaces and advances tabs to the next multiple of 4", () => {
    expect(indentColumns("    x")).toBe(4);
    expect(indentColumns("\tx")).toBe(4);
    expect(indentColumns("  \tx")).toBe(4);
    expect(indentColumns("x  ")).toBe(0);
  });
});
