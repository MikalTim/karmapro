import { describe, expect, it } from "vitest";
import { truncateMiddle } from "./middleTruncate";

// Every character is 10 wide, so a width of 100 holds ten characters.
const tenPerCharacter = (text: string): number => Array.from(text).length * 10;

describe("truncateMiddle", () => {
  it("leaves a name that fits unchanged", () => {
    expect(truncateMiddle("main.swift", 100, tenPerCharacter)).toBe("main.swift");
  });

  it("keeps the start and the end of a name that is too wide", () => {
    expect(truncateMiddle("BacktraceAnalyserWindowController.swift", 100, tenPerCharacter)).toBe("Backt…wift");
  });

  it("gives the extra character to the start", () => {
    const result = truncateMiddle("abcdefghijklmnop", 80, tenPerCharacter);
    expect(result).toBe("abcd…nop");
    expect(Array.from(result)).toHaveLength(8);
  });

  it("shows only the ellipsis when nothing else fits", () => {
    expect(truncateMiddle("abcdefghij", 10, tenPerCharacter)).toBe("…");
    expect(truncateMiddle("abcdefghij", 0, tenPerCharacter)).toBe("…");
  });

  it("does not split a character that takes two UTF-16 units", () => {
    expect(truncateMiddle("😀😀😀😀😀😀😀😀", 50, tenPerCharacter)).toBe("😀😀…😀😀");
  });
});
