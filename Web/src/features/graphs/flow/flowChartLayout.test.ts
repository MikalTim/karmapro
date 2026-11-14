import { describe, expect, it } from "vitest";
import { chartNodeSize, chartNodeText, layoutFlowChart } from "./flowChartLayout";
import type { FlowChartDTO, FlowNodeDTO } from "./flowModel";

// Every character is 6 px wide, so the sizes below are easy to check by hand.
const sixPerCharacter = (text: string) => [...text].length * 6;

const node = (id: number, kind: FlowNodeDTO["kind"], label: string): FlowNodeDTO => ({
  id,
  kind,
  label,
  highlighted: false,
});

describe("chartNodeSize", () => {
  it("pads the label by 20 x 16 and applies each kind's minimum size", () => {
    // 'START' is 30 px: 50 x 29 by padding, raised to the entry minimum of 56 x 28.
    expect(chartNodeSize(node(0, "entry", "START"), sixPerCharacter)).toEqual({ width: 56, height: 29 });
    // 'x' is 6 px: 26 x 29, raised to the block minimum of 80 x 30.
    expect(chartNodeSize(node(1, "block", "x"), sixPerCharacter)).toEqual({ width: 80, height: 30 });
    // A decision takes at least 64 x 44.
    expect(chartNodeSize(node(2, "decision", "x"), sixPerCharacter)).toEqual({ width: 64, height: 44 });
  });

  it("makes a join a fixed 16 px disc", () => {
    expect(chartNodeSize(node(3, "join", ""), sixPerCharacter)).toEqual({ width: 16, height: 16 });
  });
});

describe("layoutFlowChart", () => {
  const chain: FlowChartDTO = {
    nodes: [node(0, "entry", "START"), node(1, "block", "x"), node(2, "exit", "END")],
    edges: [
      { from: 0, to: 1, isBackEdge: false },
      { from: 1, to: 2, isBackEdge: false },
    ],
  };

  it("stacks a chain as one node per row, each row centred over the widest", () => {
    const layout = layoutFlowChart(chain, sixPerCharacter);
    // The block (80 px) is the widest row; the 56 px entry and exit are centred over it.
    expect(layout.positions.get(0)).toEqual({ x: 12, y: 0 });
    expect(layout.positions.get(1)).toEqual({ x: 0, y: 73 });
    expect(layout.positions.get(2)).toEqual({ x: 12, y: 147 });
    // Each row adds its height and a 44 px gap, then 10 px of margin.
    expect(layout.contentSize).toEqual({ width: 80, height: 230 });
  });

  it("ignores back edges when ranking", () => {
    const withBack: FlowChartDTO = {
      ...chain,
      edges: [...chain.edges, { from: 2, to: 1, isBackEdge: true }],
    };
    expect(layoutFlowChart(withBack, sixPerCharacter).positions).toEqual(layoutFlowChart(chain, sixPerCharacter).positions);
  });

  it("puts the two branches of a decision side by side, 40 px apart", () => {
    const branch: FlowChartDTO = {
      nodes: [node(0, "decision", "x"), node(1, "block", "a"), node(2, "block", "b"), node(3, "exit", "END")],
      edges: [
        { from: 0, to: 1, branch: "T", isBackEdge: false },
        { from: 0, to: 2, branch: "F", isBackEdge: false },
        { from: 1, to: 3, isBackEdge: false },
        { from: 2, to: 3, isBackEdge: false },
      ],
    };
    const layout = layoutFlowChart(branch, sixPerCharacter);
    // The branch row is 80 + 40 + 80 = 200 px wide; the decision (64 px) and the exit (56 px) centre on it.
    expect(layout.positions.get(0)).toEqual({ x: 68, y: 0 });
    expect(layout.positions.get(1)).toEqual({ x: 0, y: 88 });
    expect(layout.positions.get(2)).toEqual({ x: 120, y: 88 });
    expect(layout.positions.get(3)).toEqual({ x: 72, y: 162 });
    expect(layout.contentSize.width).toBe(200);
  });
});

describe("chartNodeText", () => {
  it("draws an entry label as one centred line, truncated to the box", () => {
    expect(chartNodeText(node(0, "entry", "START"), 30, 16, sixPerCharacter)).toEqual({ lines: ["START"], centred: true });
    // 'abcdefgh' is 48 px; the longest prefix that fits 30 px with an ellipsis is 'abcd…' (30 px).
    expect(chartNodeText(node(1, "switch", "abcdefgh"), 30, 16, sixPerCharacter)).toEqual({
      lines: ["abcd\u2026"],
      centred: true,
    });
  });

  it("wraps a block label to the left and draws only the lines that fit the height", () => {
    expect(chartNodeText(node(2, "block", "a b c"), 12, 40, sixPerCharacter)).toEqual({
      lines: ["a", "b", "c"],
      centred: false,
    });
    expect(chartNodeText(node(3, "block", "a b c"), 12, 13, sixPerCharacter).lines).toEqual(["a"]);
  });

  it("draws nothing for a join", () => {
    expect(chartNodeText(node(4, "join", ""), 4, 4, sixPerCharacter).lines).toEqual([]);
  });
});
