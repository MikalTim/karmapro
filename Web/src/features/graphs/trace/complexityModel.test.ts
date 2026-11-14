import { describe, expect, it } from "vitest";
import type { ComplexityPointDTO } from "./dto";
import {
  baseName,
  complexityColor,
  hoverText,
  labelledPoints,
  maxComplexity,
  plotRect,
  pointIndexAt,
  pointPosition,
  yTicks,
} from "./complexityModel";

const point = (name: string, complexity: number, line: number): ComplexityPointDTO => ({
  name,
  complexity,
  line,
  path: `/p/src/${name}.c`,
});

describe("plotRect", () => {
  it("keeps the AppKit margins on the left, top, right and bottom", () => {
    expect(plotRect(760, 520)).toEqual({ left: 46, top: 18, width: 690, height: 462 });
  });

  it("never shrinks below 10 px", () => {
    expect(plotRect(10, 10)).toEqual({ left: 46, top: 18, width: 10, height: 10 });
  });
});

describe("pointPosition", () => {
  const plot = plotRect(760, 520);

  it("puts zero complexity on the bottom axis and the maximum on the top edge", () => {
    expect(pointPosition(0, 3, 0, 10, plot).y).toBe(plot.top + plot.height);
    expect(pointPosition(0, 3, 10, 10, plot).y).toBe(plot.top);
  });

  it("spreads the points across the plot in source order", () => {
    expect(pointPosition(0, 3, 5, 10, plot).x).toBe(plot.left);
    expect(pointPosition(2, 3, 5, 10, plot).x).toBe(plot.left + plot.width);
  });

  it("centres a single point", () => {
    expect(pointPosition(0, 1, 5, 10, plot).x).toBe(plot.left + plot.width / 2);
  });
});

describe("yTicks", () => {
  it("steps by ceil(max / 6) and stops at the maximum", () => {
    expect(yTicks(14)).toEqual([0, 3, 6, 9, 12]);
    expect(yTicks(3)).toEqual([0, 1, 2, 3]);
  });
});

describe("complexityColor", () => {
  it("runs green at zero, yellow in the middle and red at the maximum", () => {
    expect(complexityColor(0, 10)).toBe("#2ea638");
    expect(complexityColor(5, 10)).toBe("#f2cc33");
    expect(complexityColor(10, 10)).toBe("#d92e1f");
  });
});

describe("maxComplexity", () => {
  it("is at least 1, even with no points", () => {
    expect(maxComplexity([])).toBe(1);
    expect(maxComplexity([point("a", 4, 1), point("b", 9, 2)])).toBe(9);
  });
});

describe("pointIndexAt", () => {
  it("finds the nearest point inside the tolerance and nothing beyond it", () => {
    const positions = [
      { x: 0, y: 0 },
      { x: 100, y: 0 },
    ];
    expect(pointIndexAt({ x: 98, y: 3 }, positions, 14)).toBe(1);
    expect(pointIndexAt({ x: 50, y: 0 }, positions, 14)).toBeNull();
  });
});

describe("labelledPoints", () => {
  it("labels the first point, the hovered point and points far from the last label", () => {
    const positions = [
      { x: 0, y: 0 },
      { x: 5, y: 2 },
      { x: 40, y: 0 },
      { x: 45, y: 0 },
    ];
    expect(labelledPoints(positions, null)).toEqual([true, false, true, false]);
    expect(labelledPoints(positions, 1)).toEqual([true, true, true, false]);
  });
});

describe("hover text", () => {
  it("names the file, the function, its line and its complexity", () => {
    expect(hoverText(point("main", 7, 12))).toBe("main.c · main — line 12 · complexity 7");
    expect(baseName("/a/b/c.swift")).toBe("c.swift");
  });
});
