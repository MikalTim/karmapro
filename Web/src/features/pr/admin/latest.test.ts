import { describe, expect, it } from "vitest";
import { createLatest } from "./latest";

describe("createLatest", () => {
  it("accepts only the newest request's answer", () => {
    const latest = createLatest();
    const first = latest.next();
    const second = latest.next();

    expect(latest.isLatest(first)).toBe(false);
    expect(latest.isLatest(second)).toBe(true);
  });
});
