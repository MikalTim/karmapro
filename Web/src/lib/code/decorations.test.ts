import { describe, expect, it } from "vitest";
import { type HighlightInput, buildSegments, complementRanges, gutterWidth, lineStarts, riskBackground } from "./decorations";

function input(overrides: Partial<HighlightInput>): HighlightInput {
  return {
    source: "",
    tokens: [],
    functions: [],
    classes: [],
    callSites: [],
    matches: [],
    focus: null,
    riskLines: {},
    ...overrides,
  };
}

describe("buildSegments", () => {
  it("gives every token its own run and skips unstyled text", () => {
    const segments = buildSegments(
      input({
        source: "int x;",
        tokens: [
          { location: 0, length: 3, kind: "keyword" },
          { location: 5, length: 1, kind: "plain" },
        ],
      }),
    );
    expect(segments).toEqual([
      { from: 0, to: 3, className: "tok-keyword", style: "", link: undefined },
      { from: 5, to: 6, className: "tok-plain", style: "", link: undefined },
    ]);
  });

  it("draws a function name over the syntax colour, splitting the token", () => {
    const segments = buildSegments(
      input({
        source: "int main()",
        tokens: [{ location: 0, length: 10, kind: "plain" }],
        functions: [{ name: "main", location: 4, length: 4 }],
      }),
    );
    expect(segments.map((s) => [s.from, s.to, s.className, s.link?.name])).toEqual([
      [0, 4, "tok-plain", undefined],
      [4, 8, "tok-plain cm-link-function", "main"],
      [8, 10, "tok-plain", undefined],
    ]);
  });

  it("lets a call site beat a function name beat a class name", () => {
    const range = { location: 0, length: 3 };
    const classes = [{ name: "C", ...range }];
    const functions = [{ name: "F", ...range }];
    const callSites = [{ name: "K", ...range }];
    const source = "abc";
    expect(buildSegments(input({ source, classes }))[0].link).toEqual({ kind: "class", name: "C" });
    expect(buildSegments(input({ source, classes, functions }))[0].link).toEqual({ kind: "function", name: "F" });
    expect(buildSegments(input({ source, classes, functions, callSites }))[0].link).toEqual({ kind: "call", name: "K" });
  });

  it("stacks backgrounds: find match over focus dim over risk", () => {
    const source = "aaaa\nbbbb\ncccc";
    const risky = buildSegments(input({ source, riskLines: { 2: 1 } }));
    expect(risky).toHaveLength(1);
    expect(risky[0]).toMatchObject({ from: 5, to: 9, style: `background-color: ${riskBackground(1)}` });

    // Focus keeps line 1 sharp, so line 2 is dimmed (covering its risk colour).
    const dimmed = buildSegments(input({ source, riskLines: { 2: 1 }, focus: { location: 0, length: 4 } }));
    expect(dimmed.map((s) => [s.from, s.to, s.style])).toEqual([[4, 14, "background-color: rgba(0, 0, 0, 0.55)"]]);

    // A match on top of the dim wins.
    const matched = buildSegments(
      input({ source, riskLines: { 2: 1 }, focus: { location: 0, length: 4 }, matches: [{ location: 5, length: 2 }] }),
    );
    expect(matched.map((s) => [s.from, s.to, s.style])).toEqual([
      [4, 5, "background-color: rgba(0, 0, 0, 0.55)"],
      [5, 7, "background-color: rgba(255, 230, 77, 0.6)"],
      [7, 14, "background-color: rgba(0, 0, 0, 0.55)"],
    ]);
  });

  it("clamps ranges to the text and ignores empty or out-of-range ones", () => {
    const segments = buildSegments(
      input({
        source: "abc",
        tokens: [
          { location: -2, length: 4, kind: "comment" },
          { location: 3, length: 5, kind: "string" },
          { location: 1, length: 0, kind: "number" },
        ],
        riskLines: { 0: 1, 9: 1 },
      }),
    );
    expect(segments).toEqual([{ from: 0, to: 2, className: "tok-comment", style: "", link: undefined }]);
  });

  it("measures lines in UTF-16 units", () => {
    // The emoji is two code units, so the second line starts at offset 3.
    const source = "\u{1F600}\nx";
    expect(lineStarts(source)).toEqual([0, 3]);
    const segments = buildSegments(input({ source, riskLines: { 2: 0.9 } }));
    expect(segments.map((s) => [s.from, s.to])).toEqual([[3, 4]]);
  });
});

describe("riskBackground", () => {
  it("runs from yellow at 80% to red at 100% and clamps outside", () => {
    expect(riskBackground(0.8)).toBe("rgba(255, 214, 10, 0.45)");
    expect(riskBackground(1)).toBe("rgba(255, 69, 58, 0.45)");
    expect(riskBackground(0.5)).toBe(riskBackground(0.8));
    expect(riskBackground(2)).toBe(riskBackground(1));
  });
});

describe("gutterWidth", () => {
  it("is 9 px per digit of the line count plus 26", () => {
    expect(gutterWidth("")).toBe(35);
    expect(gutterWidth("a\n".repeat(8))).toBe(35); // 9 lines
    expect(gutterWidth("a\n".repeat(9))).toBe(44); // 10 lines
    expect(gutterWidth("a\n".repeat(99))).toBe(53); // 100 lines
  });
});

describe("complementRanges", () => {
  it("returns what is outside the range", () => {
    expect(complementRanges({ location: 3, length: 4 }, 10)).toEqual([
      { location: 0, length: 3 },
      { location: 7, length: 3 },
    ]);
    expect(complementRanges({ location: 0, length: 10 }, 10)).toEqual([]);
    expect(complementRanges({ location: 0, length: 1 }, 0)).toEqual([]);
  });
});
