import { describe, expect, it } from "vitest";
import type { ContextMenuDTO } from "./sourceApi";
import {
  chipWidth,
  definitionLocation,
  definitionTitle,
  errorText,
  findCountLabel,
  findMatches,
  flowArrowsFrom,
  highlightedLinesTitle,
  howToFixPrompt,
  lineRange,
  nextMatchIndex,
  probabilityColor,
  probabilityPercent,
  riskLinesFrom,
  tokenRanges,
  typeLanguageSupported,
  typeTooltipWidth,
  type ViewerMenuEntry,
  viewerMenuEntries,
} from "./sourceModel";

function menu(overrides: Partial<ContextMenuDTO> = {}): ContextMenuDTO {
  return {
    copyEnabled: true,
    flowArrowsTitle: "Hide Flow Arrows on Code",
    flowArrowsOn: true,
    exitFocusAvailable: false,
    flowDiagramSupported: false,
    variableFlowLocation: 0,
    lineNumber: 1,
    lineText: "",
    ...overrides,
  };
}

function titles(entries: ViewerMenuEntry[]): string[] {
  return entries.map((entry) => (entry.kind === "separator" ? "-" : entry.title));
}

describe("tokenRanges and flowArrowsFrom", () => {
  it("keeps the known kinds and leaves out the rest", () => {
    expect(
      tokenRanges([
        { location: 0, length: 3, kind: "keyword" },
        { location: 4, length: 2, kind: "mystery" },
      ]),
    ).toEqual([{ location: 0, length: 3, kind: "keyword" }]);
  });

  it("keeps only the arrow kinds the overlay draws", () => {
    expect(
      flowArrowsFrom([
        { fromLine: 2, toLine: 5, kind: "branchTrue" },
        { fromLine: 3, toLine: 1, kind: "other" },
      ]),
    ).toEqual([{ fromLine: 2, toLine: 5, kind: "branchTrue" }]);
  });
});

describe("ML highlights", () => {
  it("maps each flagged line to its probability", () => {
    expect(riskLinesFrom([{ line: 6, probability: 0.9, text: "strcpy(a, b);" }])).toEqual({ 6: 0.9 });
  });

  it("rounds the list's percentage", () => {
    expect(probabilityPercent(0.8)).toBe(80);
    expect(probabilityPercent(0.999)).toBe(100);
  });

  it("blends the Probability colour from green at 60% to red at 100%", () => {
    expect(probabilityColor(0.6)).toBe("color-mix(in srgb, var(--system-red) 0%, var(--system-green))");
    expect(probabilityColor(0.8)).toBe("color-mix(in srgb, var(--system-red) 50%, var(--system-green))");
    expect(probabilityColor(1)).toBe("color-mix(in srgb, var(--system-red) 100%, var(--system-green))");
  });

  it("titles the list with its row count only when there are rows", () => {
    expect(highlightedLinesTitle(0)).toBe("Bayes highlighted lines");
    expect(highlightedLinesTitle(3)).toBe("Bayes highlighted lines (3)");
  });
});

describe("viewerMenuEntries", () => {
  it("lists the function and variable items in AppKit's order", () => {
    const entries = viewerMenuEntries(
      menu({
        copyEnabled: false,
        flowArrowsOn: false,
        flowArrowsTitle: "Show Flow Arrows on Code",
        exitFocusAvailable: true,
        functionName: "parse",
        variableName: "buf",
      }),
      false,
    );
    expect(titles(entries)).toEqual([
      "Copy",
      "-",
      "Show Flow Arrows on Code",
      "-",
      "Focus on 'parse'",
      "-",
      "Exit Focus Mode",
      "-",
      "Complexity distribution",
      "-",
      "Show Flow Diagram for parse",
      "Simulate 'parse' in the Debugger",
      "Show reachability of 'parse'",
      "-",
      "Follow the variable 'buf'",
      "-",
      "Backtrace Analyser…",
      "-",
      "Find external entries",
      "-",
      "(AI) How to fix it",
    ]);
  });

  it("drops the function and variable items when the pointer is on neither", () => {
    const entries = viewerMenuEntries(menu(), false);
    expect(titles(entries)).toEqual([
      "Copy",
      "-",
      "Hide Flow Arrows on Code",
      "-",
      "Complexity distribution",
      "-",
      "Backtrace Analyser…",
      "-",
      "Find external entries",
      "-",
      "(AI) How to fix it",
    ]);
  });

  it("checks the flow arrows item while arrows are on and disables Copy with nothing to copy", () => {
    const entries = viewerMenuEntries(menu({ copyEnabled: false }), true);
    const copy = entries[0];
    const flow = entries[2];
    expect(copy).toMatchObject({ kind: "item", id: "copy", disabled: true, shortcut: "⌘C" });
    expect(flow).toMatchObject({ kind: "item", id: "flowArrows", checked: true });
  });

  it("uses the Ctrl modifier name for Copy off macOS", () => {
    expect(viewerMenuEntries(menu(), false)[0]).toMatchObject({ shortcut: "Ctrl+C" });
  });
});

describe("findMatches", () => {
  it("finds every case-insensitive occurrence", () => {
    expect(findMatches("Foo foo FOO", "foo")).toEqual([
      { location: 0, length: 3 },
      { location: 4, length: 3 },
      { location: 8, length: 3 },
    ]);
  });

  it("does not let matches overlap, like the search loop that moves past each match", () => {
    expect(findMatches("aaaa", "aa")).toEqual([
      { location: 0, length: 2 },
      { location: 2, length: 2 },
    ]);
  });

  it("counts offsets in UTF-16 units, so text after an emoji lines up with the editor", () => {
    expect(findMatches("😀 Foo", "foo")).toEqual([{ location: 3, length: 3 }]);
  });

  it("treats the term literally", () => {
    expect(findMatches("abc a.c", "a.c")).toEqual([{ location: 4, length: 3 }]);
  });

  it("finds nothing for an empty term", () => {
    expect(findMatches("anything", "")).toEqual([]);
  });
});

describe("find bar", () => {
  it("labels the position, or the lack of matches", () => {
    expect(findCountLabel("", 0, -1)).toBe("");
    expect(findCountLabel("x", 0, -1)).toBe("No matches");
    expect(findCountLabel("x", 5, 1)).toBe("2/5");
  });

  it("moves forward and wraps after the last match", () => {
    expect(nextMatchIndex(-1, 3)).toBe(0);
    expect(nextMatchIndex(1, 3)).toBe(2);
    expect(nextMatchIndex(2, 3)).toBe(0);
    expect(nextMatchIndex(0, 0)).toBe(-1);
  });
});

describe("texts the viewer hands to other windows", () => {
  it("builds the How-to-fix question exactly as the assistant receives it", () => {
    expect(howToFixPrompt("/src/main.c", 6, "  strcpy(buf, argv[1]);")).toBe(
      "How to fix the vulnerability at: /src/main.c:6\n\n  strcpy(buf, argv[1]);",
    );
  });

  it("names the definition window after its file and gives its location", () => {
    expect(definitionTitle("/src/util/main.c")).toBe("Definition — main.c");
    expect(definitionLocation("/src/util/main.c", 12)).toBe("/src/util/main.c — line 12");
    expect(definitionLocation("/src/util/main.c", null)).toBe("/src/util/main.c");
  });

  it("gives the first line the start of the file and the last line the end", () => {
    expect(lineRange("ab\ncd\n", 1)).toEqual({ location: 0, length: 2 });
    expect(lineRange("ab\ncd\n", 2)).toEqual({ location: 3, length: 2 });
    expect(lineRange("ab\ncd\n", 3)).toEqual({ location: 6, length: 0 });
    expect(lineRange("ab\ncd\n", 4)).toBeNull();
  });

  it("reads the type languages from the extension, whatever its case", () => {
    expect(typeLanguageSupported("c")).toBe(true);
    expect(typeLanguageSupported("JAVA")).toBe(true);
    expect(typeLanguageSupported("py")).toBe(false);
    expect(typeLanguageSupported("constructor")).toBe(false);
  });

  it("sizes the type tooltip to its text, with a 60 px floor", () => {
    expect(typeTooltipWidth(10)).toBe(60);
    expect(typeTooltipWidth(200.2)).toBe(221);
  });

  it("gives every focus chip at least 50 px", () => {
    expect(chipWidth(4)).toBe(50);
    expect(chipWidth(60)).toBe(88);
  });

  it("uses the message of a failure, or the text of anything else", () => {
    expect(errorText(new Error("Could not read file:\n/x"))).toBe("Could not read file:\n/x");
    expect(errorText("plain")).toBe("plain");
  });
});
