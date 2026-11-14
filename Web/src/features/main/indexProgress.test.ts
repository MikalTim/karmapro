import { describe, expect, it } from "vitest";
import { formatRemaining, indexFraction, indexStatus } from "./indexProgress";

describe("indexFraction", () => {
  it("is the share of files done, and zero until the total is known", () => {
    expect(indexFraction(5, 10)).toBe(0.5);
    expect(indexFraction(0, 0)).toBe(0);
  });
});

describe("formatRemaining", () => {
  it("writes seconds below a minute and whole minutes above", () => {
    expect(formatRemaining(0.4)).toBe("1s");
    expect(formatRemaining(42.4)).toBe("42s");
    expect(formatRemaining(120)).toBe("2 min");
  });
});

describe("indexStatus", () => {
  it("says the time is being estimated before the first file is done", () => {
    expect(indexStatus(0, 10, 5)).toBe("Indexed 0 of 10 source files — estimating time…");
  });

  it("estimates the time left from the pace so far", () => {
    expect(indexStatus(5, 10, 10)).toBe("Indexed 5 of 10 source files — about 10s left");
    expect(indexStatus(10, 20, 120)).toBe("Indexed 10 of 20 source files — about 2 min left");
  });

  it("says it is finishing once every file is done", () => {
    expect(indexStatus(10, 10, 30)).toBe("Indexed 10 of 10 source files — finishing…");
  });
});
