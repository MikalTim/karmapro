import { describe, expect, it } from "vitest";
import { progressRepoLine, progressTitle, shortened } from "./prText";
import type { PRItem } from "./prTypes";

function item(overrides: Partial<PRItem> = {}): PRItem {
  return {
    repoID: "repo-1",
    repoSlug: "owner/name",
    prID: 99,
    number: 12,
    title: "Fix login",
    author: "ada",
    headBranch: "fix/login",
    baseBranch: "main",
    webURL: "https://example.com/owner/name/pull/12",
    isNew: true,
    ...overrides,
  };
}

describe("shortened", () => {
  it("leaves text that fits unchanged", () => {
    expect(shortened("abc", 3)).toBe("abc");
  });

  it("cuts to the limit with an ellipsis, counting characters as Swift does", () => {
    expect(shortened("abcdef", 4)).toBe("abc\u2026");
    // "e" with a combining accent is one character, so this fits in four.
    expect(shortened("e\u0301bcd", 4)).toBe("e\u0301bcd");
    expect(shortened("\u{1F44D}\u{1F3FD}\u{1F44D}\u{1F3FD}\u{1F44D}\u{1F3FD}", 2)).toBe("\u{1F44D}\u{1F3FD}\u2026");
  });
});

describe("progress window text", () => {
  it("shows the number and title on the first line", () => {
    expect(progressTitle(item())).toBe("#12 Fix login");
  });

  it("cuts a long title to 72 characters", () => {
    const long = "a".repeat(100);

    expect(progressTitle(item({ title: long }))).toBe(`#12 ${"a".repeat(71)}\u2026`);
  });

  it("shows the repository and the branches on the second line", () => {
    expect(progressRepoLine(item())).toBe("owner/name  \u00B7  fix/login \u2192 main");
  });

  it("cuts a long head branch to 28 characters", () => {
    const branch = "feature/" + "b".repeat(40);

    expect(progressRepoLine(item({ headBranch: branch }))).toBe(
      `owner/name  \u00B7  ${"feature/" + "b".repeat(19)}\u2026 \u2192 main`,
    );
  });
});
