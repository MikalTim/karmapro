import { describe, expect, it } from "vitest";
import { DragTracker } from "./drag";
import { arrowheadPath, orthogonalPath, pointOnLine, wheelZoomFactor, zoomAt } from "./geometry";

describe("orthogonalPath", () => {
  it("goes vertically to a channel halfway between the nodes, across, then to the end", () => {
    expect(orthogonalPath({ x: 10, y: 0 }, { x: 50, y: 100 })).toBe("M10 0L10 50L50 50L50 100");
    expect(orthogonalPath({ x: 10, y: 0 }, { x: 50, y: 100 }, 6)).toBe("M10 0L10 56L50 56L50 100");
  });
});

describe("arrowheadPath", () => {
  it("draws two 9 px strokes 0.4 rad either side of the reverse direction", () => {
    const d = arrowheadPath({ x: 0, y: 0 }, { x: 100, y: 0 });
    const [tip, left, tip2, right] = d.match(/-?\d+(\.\d+)?(e-?\d+)? -?\d+(\.\d+)?(e-?\d+)?/g) ?? [];
    expect(tip).toBe("100 0");
    expect(tip2).toBe("100 0");
    const [lx, ly] = left.split(" ").map(Number);
    const [rx, ry] = right.split(" ").map(Number);
    expect(Math.hypot(lx - 100, ly)).toBeCloseTo(9);
    expect(lx).toBeCloseTo(100 - 9 * Math.cos(-0.4));
    expect(ly).toBeCloseTo(-9 * Math.sin(-0.4));
    expect(rx).toBeCloseTo(lx);
    expect(ry).toBeCloseTo(-ly);
  });
});

describe("pointOnLine", () => {
  it("moves along the line and stays put for a zero-length line", () => {
    expect(pointOnLine({ x: 0, y: 0 }, { x: 3, y: 4 }, 5)).toEqual({ x: 3, y: 4 });
    expect(pointOnLine({ x: 1, y: 1 }, { x: 1, y: 1 }, 5)).toEqual({ x: 1, y: 1 });
  });
});

describe("zoomAt", () => {
  const start = { scale: 1, offsetX: 0, offsetY: 0 };

  it("keeps the content point under the pointer fixed", () => {
    const next = zoomAt(start, 2, { x: 100, y: 50 }, 0.4, 6);
    expect(next).toEqual({ scale: 2, offsetX: -100, offsetY: -50 });
    // The content point that was at (100, 50) is still at (100, 50).
    expect((100 - (next?.offsetX ?? 0)) / (next?.scale ?? 1)).toBe(100);
  });

  it("clamps to the scale limits and reports no change at a limit", () => {
    expect(zoomAt(start, 100, { x: 0, y: 0 }, 0.4, 6)?.scale).toBe(6);
    expect(zoomAt({ scale: 6, offsetX: 0, offsetY: 0 }, 2, { x: 0, y: 0 }, 0.4, 6)).toBeNull();
    expect(zoomAt(start, 0.01, { x: 0, y: 0 }, 0.4, 6)?.scale).toBe(0.4);
    expect(zoomAt(start, -1, { x: 0, y: 0 }, 0.4, 6)).toBeNull();
  });
});

describe("wheelZoomFactor", () => {
  it("is 1 + delta / 60, clamped to 0.2...3, with a line wheel counting ten times", () => {
    expect(wheelZoomFactor(-6, 0)).toBeCloseTo(1.1);
    expect(wheelZoomFactor(6, 0)).toBeCloseTo(0.9);
    expect(wheelZoomFactor(-1, 1)).toBeCloseTo(1 + 10 / 60);
    expect(wheelZoomFactor(-10000, 0)).toBe(3);
    expect(wheelZoomFactor(10000, 0)).toBe(0.2);
  });
});

describe("DragTracker", () => {
  const transform = { scale: 2, offsetX: 10, offsetY: 20 };

  it("reports a press that stays within 4 px as a click on the node", () => {
    const tracker = new DragTracker();
    tracker.down({ x: 100, y: 100 }, "a", { x: 5, y: 5 }, transform);
    tracker.move({ x: 102, y: 102 }, 2);
    expect(tracker.up()).toBe("a");
  });

  it("drags a node by the pointer movement divided by the scale and then does not click", () => {
    const tracker = new DragTracker();
    tracker.down({ x: 100, y: 100 }, "a", { x: 5, y: 5 }, transform);
    expect(tracker.move({ x: 120, y: 90 }, 2)).toEqual({ node: "a", position: { x: 15, y: 0 } });
    expect(tracker.up()).toBeNull();
  });

  it("pans from the offset the press started with when it starts on empty space", () => {
    const tracker = new DragTracker();
    tracker.down({ x: 100, y: 100 }, null, { x: 0, y: 0 }, transform);
    expect(tracker.move({ x: 130, y: 90 }, 2)).toEqual({ offset: { x: 40, y: 10 } });
    expect(tracker.up()).toBeNull();
    expect(tracker.move({ x: 1, y: 1 }, 2)).toBeNull();
  });
});
