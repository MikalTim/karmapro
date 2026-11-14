import { describe, expect, it } from "vitest";
import { captionLayout, cellBox, columnCount, contentHeight, countTextColor, heatColor, truncateMiddle } from "./heatmapGeometry";

describe("grid layout", () => {
  it("fits as many 94 px columns as the width allows, and at least one", () => {
    expect(columnCount(0)).toBe(1);
    expect(columnCount(292)).toBe(3);
    expect(columnCount(291)).toBe(2);
  });

  it("is one row tall while empty, plus the gap", () => {
    expect(contentHeight(0, 600)).toBe(134);
  });

  it("adds a row for every started line of cells", () => {
    expect(contentHeight(7, 292)).toBe(382);
    expect(contentHeight(6, 292)).toBe(258);
  });

  it("places a cell and its file name under it", () => {
    expect(cellBox(4, 3)).toEqual({ x: 104, y: 134, size: 84, captionY: 220 });
  });
});

describe("colours", () => {
  it("runs from blue at 0 to red at 1, through the stops", () => {
    expect(heatColor(0)).toBe("rgb(61, 99, 219)");
    expect(heatColor(0.5)).toBe("rgb(89, 199, 79)");
    expect(heatColor(1)).toBe("rgb(232, 61, 46)");
  });

  it("blends between two stops", () => {
    expect(heatColor(0.125)).toBe("rgb(70, 144, 200)");
  });

  it("clamps the share to 0...1", () => {
    expect(heatColor(-1)).toBe(heatColor(0));
    expect(heatColor(2)).toBe(heatColor(1));
  });

  it("writes the count in white only on the hottest cells", () => {
    expect(countTextColor(0.6)).toBe("#000");
    expect(countTextColor(0.61)).toBe("#fff");
  });
});

describe("file names", () => {
  // A fake font: every character is 0.6 em wide.
  const measure = (text: string, fontPx: number) => text.length * fontPx * 0.6;

  it("uses 11 px for a name up to 80 px wide", () => {
    const name = "abcdefghijkl";
    expect(captionLayout(name, measure)).toEqual({ fontPx: 11, text: name });
  });

  it("uses 9 px for a name wider than 80 px at 11 px", () => {
    expect(captionLayout("abcdefghijklm", measure)).toEqual({ fontPx: 9, text: "abcdefghijklm" });
  });

  it("truncates in the middle to the cell width", () => {
    const name = "src/very/long/path/to/the/file.c";
    const layout = captionLayout(name, measure);
    expect(layout.fontPx).toBe(9);
    expect(layout.text).toContain("…");
    expect(measure(layout.text, 9)).toBeLessThanOrEqual(84);
    expect(layout.text.startsWith("src/")).toBe(true);
    expect(layout.text.endsWith("file.c")).toBe(true);
  });

  it("keeps a name that fits unchanged", () => {
    expect(truncateMiddle("abc", 10, (text) => text.length)).toBe("abc");
  });

  it("keeps the longest start and end that fit, with an ellipsis between", () => {
    expect(truncateMiddle("abcdefghijklmnopqrstuvwxyz", 10, (text) => text.length)).toBe("abcde…wxyz");
  });
});
