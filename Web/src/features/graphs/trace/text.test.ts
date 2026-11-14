import { describe, expect, it } from "vitest";
import { ellipsize, fitLine, wrapText } from "./text";

// Seven px per character keeps the widths exact.
const measure = (text: string) => text.length * 7;

describe("wrapText", () => {
  it("breaks at spaces so that no line is wider than the limit", () => {
    expect(wrapText("alpha beta gamma", "f", 70, measure)).toEqual(["alpha beta", "gamma"]);
    expect(wrapText("alpha beta", "f", 70, measure)).toEqual(["alpha beta"]);
  });

  it("breaks a word that is wider than the limit by characters", () => {
    expect(wrapText("abcdefghij", "f", 35, measure)).toEqual(["abcde", "fghij"]);
  });

  it("is empty for empty text", () => {
    expect(wrapText("", "f", 70, measure)).toEqual([]);
  });
});

describe("fitLine", () => {
  it("returns the text unchanged when it fits", () => {
    expect(fitLine("short", "f", 70, measure)).toBe("short");
  });

  it("cuts the text and ends it with an ellipsis when it does not", () => {
    expect(fitLine("a long line of code", "f", 70, measure)).toBe("a long li…");
  });
});

describe("ellipsize", () => {
  it("always ends with an ellipsis, even when the text would fit", () => {
    expect(ellipsize("abc", "f", 70, measure)).toBe("abc…");
    expect(ellipsize("abcdefghijklmnop", "f", 70, measure)).toBe("abcdefghi…");
  });
});
