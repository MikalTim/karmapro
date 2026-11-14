import { describe, expect, it } from "vitest";
import { isAlternateRow, lastColumnWidth, stripeBackground } from "./stripes";

describe("stripeBackground", () => {
  it("starts with the plain band when the last row was the alternate one", () => {
    expect(stripeBackground(20, false)).toBe(
      "repeating-linear-gradient(to bottom, transparent 0, transparent 20px, var(--row-alt) 20px, var(--row-alt) 40px)",
    );
  });

  it("starts with the alternate band when the last row was a plain one", () => {
    expect(stripeBackground(22, true)).toBe(
      "repeating-linear-gradient(to bottom, var(--row-alt) 0, var(--row-alt) 22px, transparent 22px, transparent 44px)",
    );
  });
});

describe("isAlternateRow", () => {
  it("keeps row 0 plain and alternates from there", () => {
    expect([0, 1, 2, 3].map(isAlternateRow)).toEqual([false, true, false, true]);
  });
});

describe("lastColumnWidth", () => {
  it("takes what the other columns leave", () => {
    expect(lastColumnWidth(900, 500, 30, 420)).toBe(400);
  });

  it("shrinks to the minimum width when the view is narrow", () => {
    expect(lastColumnWidth(300, 500, 30, 420)).toBe(30);
  });

  it("keeps its own width until the view has been measured", () => {
    expect(lastColumnWidth(0, 500, 30, 420)).toBe(420);
  });
});
