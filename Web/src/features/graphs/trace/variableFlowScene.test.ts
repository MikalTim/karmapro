import { describe, expect, it } from "vitest";
import type { ViewTransform } from "../../../lib/diagram/geometry";
import type { TraceFonts } from "./text";
import { buildVariableScene, fitView, rootBoxAt, tapAt } from "./variableFlowScene";
import type { VariableLayout } from "./variableFlowLayout";

const measure = (text: string) => text.length * 7;
const fonts: TraceFonts = {
  ui: (size, weight) => `${weight} ${size}px test`,
  mono: (size, weight) => `${weight} ${size}px mono`,
};

const layout: VariableLayout = {
  flowNodes: [],
  flowEdges: [],
  boxes: [
    {
      id: "b1",
      root: true,
      rect: { x: 100, y: 100, width: 320, height: 70 },
      header: "f (x)",
      subtitle: "a.c — called from line 4",
      rows: [{ line: 5, text: "  use" }],
      moreCount: 0,
      deeperCollapsed: false,
    },
  ],
  taps: [{ box: "b1", rect: { x: 106, y: 140, width: 316, height: 18 }, path: "/p/a.c", line: 5 }],
  callEdges: [],
  returnEdges: [],
  contentWidth: 500,
  contentHeight: 300,
};

const state = { flowPositions: new Map(), boxOffsets: new Map([["b1", { x: 10, y: 0 }]]) };
const zoomed: ViewTransform = { scale: 2, offsetX: 0, offsetY: 0 };

describe("fitView", () => {
  it("scales the content to fit the window with a 20 px margin, at most 2x", () => {
    const view = fitView(400, 300, 800, 600);
    expect(view.scale).toBeCloseTo((600 - 40) / 300);
    expect(view.offsetX).toBeCloseTo((800 - 400 * view.scale) / 2);
  });

  it("never scales above 2x", () => {
    expect(fitView(10, 10, 800, 600).scale).toBe(2);
  });
});

describe("hit tests", () => {
  it("finds a use line where the box is drawn, after the box was dragged", () => {
    // The box moved 10 px right in content space, so its use line sits at x 116..432.
    expect(tapAt({ x: 300, y: 290 }, layout, state, zoomed)?.line).toBe(5);
    expect(tapAt({ x: 10, y: 10 }, layout, state, zoomed)).toBeNull();
  });

  it("finds the root box under a point", () => {
    expect(rootBoxAt({ x: 230, y: 210 }, layout, state, zoomed)?.id).toBe("b1");
    expect(rootBoxAt({ x: 10, y: 10 }, layout, state, zoomed)).toBeNull();
  });
});

describe("buildVariableScene", () => {
  it("shows only the empty-state text before a trace is shown", () => {
    const items = buildVariableScene(layout, state, zoomed, false, fonts, measure);
    expect(items).toEqual([
      { shape: "text", x: 20, y: 20, text: "No variable flow to display.", font: "400 13px test", fill: "var(--secondary-label)", anchor: "start" },
    ]);
  });

  it("draws callee boxes at their screen position, with the header scaled to the zoom", () => {
    const items = buildVariableScene(layout, state, zoomed, true, fonts, measure);
    const frame = items.find((item) => item.shape === "box");
    expect(frame).toMatchObject({ x: 220, y: 200, width: 640, height: 140 });
    const header = items.find((item) => item.shape === "text" && item.text === "f (x)");
    expect(header).toMatchObject({ font: "700 24px test" });
  });
});
