import { describe, expect, it } from "vitest";
import { truncateMiddle, truncateTail, wrapLines } from "./textFit";

// Every character is 10 px wide, so widths are easy to read.
const tenPerCharacter = (text: string) => [...text].length * 10;

describe("wrapLines", () => {
  it("keeps a line whose width fits", () => {
    expect(wrapLines("ab cd", 50, tenPerCharacter)).toEqual(["ab cd"]);
  });

  it("breaks at spaces when the next word would not fit", () => {
    expect(wrapLines("ab cd ef", 50, tenPerCharacter)).toEqual(["ab cd", "ef"]);
  });

  it("breaks a word wider than the whole line between characters", () => {
    expect(wrapLines("abcdefg", 30, tenPerCharacter)).toEqual(["abc", "def", "g"]);
  });

  it("starts a new line for each newline and returns nothing for an empty label", () => {
    expect(wrapLines("ab\ncd", 100, tenPerCharacter)).toEqual(["ab", "cd"]);
    expect(wrapLines("", 100, tenPerCharacter)).toEqual([]);
  });
});

describe("truncateTail", () => {
  it("returns the text unchanged when it fits", () => {
    expect(truncateTail("abc", 30, tenPerCharacter)).toBe("abc");
  });

  it("keeps the longest prefix that fits with an ellipsis", () => {
    expect(truncateTail("abcdef", 40, tenPerCharacter)).toBe("abc\u2026");
  });
});

describe("truncateMiddle", () => {
  it("keeps the longest head and tail that fit around an ellipsis", () => {
    // Six 10 px characters fit 60 px: 'abc', the ellipsis and 'gh'.
    expect(truncateMiddle("abcdefgh", 60, tenPerCharacter)).toBe("abc\u2026gh");
  });

  it("returns the text unchanged when it fits", () => {
    expect(truncateMiddle("file.c", 100, tenPerCharacter)).toBe("file.c");
  });
});
