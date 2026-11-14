import { describe, expect, it } from "vitest";
import { formatRemaining, indexedProgressText, progressFraction } from "./progress";

describe("formatRemaining", () => {
  it("writes sub-second times as 1s, seconds up to a minute, and minutes beyond", () => {
    expect(formatRemaining(0.4)).toBe("1s");
    expect(formatRemaining(42.6)).toBe("43s");
    expect(formatRemaining(90)).toBe("2 min");
  });
});

describe("indexedProgressText", () => {
  it("says it is estimating before any file is done", () => {
    expect(indexedProgressText(0, 10, 0)).toBe("Indexed 0 of 10 source files — estimating time…");
  });

  it("extrapolates the time left from the files done so far", () => {
    expect(indexedProgressText(2, 10, 4)).toBe("Indexed 2 of 10 source files — about 16s left");
  });

  it("says it is finishing once every file is done", () => {
    expect(indexedProgressText(10, 10, 12)).toBe("Indexed 10 of 10 source files — finishing…");
  });
});

describe("progressFraction", () => {
  it("is the share of files done, or nothing while the total is unknown", () => {
    expect(progressFraction(3, 4)).toBe(0.75);
    expect(progressFraction(0, 0)).toBeUndefined();
  });
});
