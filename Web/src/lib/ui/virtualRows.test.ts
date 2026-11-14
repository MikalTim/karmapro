import { describe, expect, it } from "vitest";
import { rowAtOffset, rowOffsets, visibleRowWindow } from "./virtualRows";

describe("measured table row offsets", () => {
  it("uses the minimum for unknown rows and the measured height for wrapping rows", () => {
    expect(rowOffsets([0, 90, 12, 40], (height) => height, 28)).toEqual([0, 28, 118, 146, 186]);
  });

  it("finds a tall row and assigns exact boundaries to the next row", () => {
    const offsets = [0, 28, 118, 146];
    expect(rowAtOffset(offsets, 27)).toBe(0);
    expect(rowAtOffset(offsets, 28)).toBe(1);
    expect(rowAtOffset(offsets, 117.5)).toBe(1);
    expect(rowAtOffset(offsets, 118)).toBe(2);
    expect(rowAtOffset(offsets, 1000)).toBe(2);
  });

  it("handles an empty list", () => {
    expect(rowOffsets([], () => 28, 28)).toEqual([0]);
    expect(visibleRowWindow([0], 100, 400, 20)).toEqual({ first: 0, last: 0 });
  });

  it("does not render the row starting at the viewport's bottom edge without overscan", () => {
    expect(visibleRowWindow([0, 28, 118, 146, 174], 28, 90, 0)).toEqual({ first: 1, last: 2 });
    expect(visibleRowWindow([0, 28, 118, 146, 174], 28, 91, 0)).toEqual({ first: 1, last: 3 });
  });

  it("includes the tall row intersecting the top and clamps overscan at either end", () => {
    const offsets = [0, 28, 118, 146, 174];
    expect(visibleRowWindow(offsets, 80, 40, 1)).toEqual({ first: 0, last: 4 });
    expect(visibleRowWindow(offsets, 150, 400, 20)).toEqual({ first: 0, last: 4 });
  });

  it("keeps a tall final row reachable in a list above the virtualization threshold", () => {
    const heights = Array.from({ length: 600 }, (_, index) => (index === 0 || index === 599 ? 180 : 28));
    const offsets = rowOffsets(heights, (height) => height, 28);
    expect(visibleRowWindow(offsets, offsets[600] - 100, 100, 20)).toEqual({ first: 579, last: 600 });
    expect(rowAtOffset(offsets, offsets[600] - 1)).toBe(599);
  });
});
