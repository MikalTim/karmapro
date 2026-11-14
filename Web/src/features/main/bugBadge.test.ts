import { describe, expect, it } from "vitest";
import { bugBadgeText } from "./bugBadge";

describe("bugBadgeText", () => {
  it("hides the badge when no bug is open", () => {
    expect(bugBadgeText(0)).toBeNull();
  });

  it("shows the count up to ninety-nine", () => {
    expect(bugBadgeText(1)).toBe("1");
    expect(bugBadgeText(99)).toBe("99");
  });

  it("shows 99+ above ninety-nine", () => {
    expect(bugBadgeText(100)).toBe("99+");
  });
});
