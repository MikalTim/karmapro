import { describe, expect, it } from "vitest";
import { classifyFailure, messageOf, resultLine, statusColour, statusLine, toneNamed } from "./status";

describe("status colours", () => {
  it("shows errors in red, warnings in orange and information in the secondary label colour", () => {
    expect(statusColour("error")).toBe("var(--system-red)");
    expect(statusColour("warning")).toBe("var(--system-orange)");
    expect(statusColour("info")).toBe("var(--secondary-label)");
  });

  it("turns a failed server result into an error line and a successful one into information", () => {
    expect(resultLine({ text: "Saved alice for GitHub.", success: true })).toEqual(
      statusLine("Saved alice for GitHub.", "info"),
    );
    expect(resultLine({ text: "alice: 401 Unauthorized", success: false }).tone).toBe("error");
  });

  it("reads an unknown server tone as information", () => {
    expect(toneNamed("error")).toBe("error");
    expect(toneNamed("warning")).toBe("warning");
    expect(toneNamed("something else")).toBe("info");
    expect(toneNamed(null)).toBe("info");
  });
});

describe("failure routing", () => {
  it("keeps a plain message in the status line", () => {
    expect(classifyFailure("Paste a token to save.")).toEqual({ kind: "status", text: "Paste a token to save." });
  });

  it("shows a title and detail joined by a blank line as an alert", () => {
    expect(classifyFailure("No usable account for this repository\n\nAdd a read-only token in Accounts… first.")).toEqual({
      kind: "alert",
      title: "No usable account for this repository",
      detail: "Add a read-only token in Accounts… first.",
    });
  });

  it("keeps any later blank lines inside the detail", () => {
    expect(classifyFailure("Could not clear the cache\n\nfirst\n\nsecond")).toEqual({
      kind: "alert",
      title: "Could not clear the cache",
      detail: "first\n\nsecond",
    });
  });

  it("reads the message of an error and stringifies anything else", () => {
    expect(messageOf(new Error("boom"))).toBe("boom");
    expect(messageOf("plain")).toBe("plain");
  });
});
