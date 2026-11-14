import { describe, expect, it } from "vitest";
import { statusColor } from "./status";

describe("statusColor", () => {
  it("colours each level as the AppKit status line does", () => {
    expect(statusColor("info")).toBe("var(--secondary-label)");
    expect(statusColor("error")).toBe("var(--system-red)");
    expect(statusColor("warning")).toBe("var(--system-orange)");
    expect(statusColor("success")).toBe("var(--system-green)");
  });

  it("uses the secondary label colour for an unknown level", () => {
    expect(statusColor("")).toBe("var(--secondary-label)");
  });
});
