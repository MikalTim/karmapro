import { describe, expect, it } from "vitest";
import { middleTruncate } from "./truncate";

// Every character is 10 px wide, so a candidate fits when it has at most available / 10 characters.
const tenPerCharacter = (candidate: string) => candidate.length * 10;

describe("middle truncation", () => {
  it("leaves text that fits unchanged", () => {
    expect(middleTruncate("owner/name", 100, tenPerCharacter)).toBe("owner/name");
  });

  it("keeps the start and the end and puts the ellipsis between them", () => {
    // Ten characters fit including the ellipsis, so nine are kept: five at the start and four at the end.
    expect(middleTruncate("Changed files only", 100, tenPerCharacter)).toBe("Chang\u2026only");
  });

  it("gives the start the extra character when the kept count is odd", () => {
    // Nine characters fit including the ellipsis, so eight are kept: four at each end.
    expect(middleTruncate("abcdefghijkl", 90, tenPerCharacter)).toBe("abcd\u2026ijkl");
    // Eight fit, so seven are kept: four at the start and three at the end.
    expect(middleTruncate("abcdefghijkl", 80, tenPerCharacter)).toBe("abcd\u2026jkl");
  });

  it("shows only the ellipsis when nothing else fits", () => {
    expect(middleTruncate("abcdefghijkl", 10, tenPerCharacter)).toBe("\u2026");
    expect(middleTruncate("abcdefghijkl", 0, tenPerCharacter)).toBe("\u2026");
  });
});
