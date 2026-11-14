import { describe, expect, it } from "vitest";
import { FLOW_WIDTH, SOURCE_MIN_WIDTH, TREE_WIDTH, clampFlowWidth, clampTreeWidth } from "./layout";

describe("pane widths", () => {
  it("starts the tree at 300 and the flow panel at 320, as the split view does", () => {
    expect(TREE_WIDTH.initial).toBe(300);
    expect(FLOW_WIDTH.initial).toBe(320);
  });

  it("never narrows the tree below its minimum", () => {
    expect(clampTreeWidth(50, 1600, 320)).toBe(TREE_WIDTH.min);
  });

  it("leaves the source viewer its minimum width when the tree is dragged wide", () => {
    const total = 1600;
    const flow = 320;
    const tree = clampTreeWidth(2000, total, flow);
    expect(total - tree - flow - 2 * 6).toBe(SOURCE_MIN_WIDTH);
  });

  it("never narrows the flow panel below its minimum", () => {
    expect(clampFlowWidth(100, 1600, 306)).toBe(FLOW_WIDTH.min);
  });

  it("leaves the source viewer its minimum width when the flow panel is dragged wide", () => {
    const total = 1600;
    const flow = clampFlowWidth(2000, total, 306);
    expect(total - 306 - flow - 2 * 6).toBe(SOURCE_MIN_WIDTH);
  });

  it("keeps the minimum when the window is too narrow for the viewer", () => {
    expect(clampTreeWidth(400, 800, 320)).toBe(TREE_WIDTH.min);
  });
});
