// Tests for the rich text model the editor works on (`../richText.ts`): the document
// conversion, the link styling, toolbar formatting and the caret helpers.
import { describe, expect, it } from "vitest";
import {
  applyFormat,
  applyWikiLinks,
  caretStyleAfter,
  characterCount,
  DEFAULT_STYLE,
  flatten,
  formatStyle,
  fromDocument,
  linkTarget,
  replaceRange,
  samePieces,
  toDocument,
  typingStyle,
  wikiLinkURL,
  type Piece,
  type TextStyle,
  type WikiDocument,
  type WikiRun,
} from "../richText";

function runOf(text: string, extra: Partial<WikiRun> = {}): WikiRun {
  return { text, bold: false, italic: false, underline: false, code: false, heading: false, ...extra };
}

function documentOf(...paragraphs: WikiRun[][]): WikiDocument {
  return { paragraphs: paragraphs.map((runs) => ({ runs })) };
}

function textWhere(pieces: Piece[], keep: (style: TextStyle) => boolean): string {
  return pieces
    .filter((piece) => keep(piece.style))
    .map((piece) => piece.text)
    .join("");
}

describe("fromDocument and toDocument", () => {
  it("round-trips every run style, links and empty paragraphs", () => {
    const document = documentOf(
      [runOf("Title", { heading: true, bold: true }), runOf(" and "), runOf("code", { code: true })],
      [],
      [runOf("Beta", { link: "wiki://page/Beta", underline: true }), runOf("x", { italic: true })],
    );
    expect(toDocument(fromDocument(document))).toEqual(document);
  });

  it("saves the dimmed brackets as plain text and omits the link from plain runs", () => {
    const saved = toDocument(applyWikiLinks(fromDocument(documentOf([runOf("[[Beta]]")]))));
    const runs = saved.paragraphs[0].runs;
    expect(runs.map((run) => run.text)).toEqual(["[[", "Beta", "]]"]);
    expect(Object.keys(runs[0])).toEqual(["text", "bold", "italic", "underline", "code", "heading"]);
    expect(runs[1].link).toBe("wiki://page/Beta");
  });

  it("gives no paragraphs for an empty page", () => {
    expect(toDocument([])).toEqual({ paragraphs: [] });
  });
});

describe("applyWikiLinks", () => {
  it("turns [[Name]] into a link and dims the brackets without changing the text", () => {
    const pieces = applyWikiLinks(fromDocument(documentOf([runOf("See [[Buffer Overflows]] now")])));
    expect(flatten(pieces)).toBe("See [[Buffer Overflows]] now");
    expect(textWhere(pieces, (style) => style.link !== null)).toBe("Buffer Overflows");
    expect(pieces.find((piece) => piece.style.link !== null)?.style.link).toBe("wiki://page/Buffer%20Overflows");
    expect(textWhere(pieces, (style) => style.dim)).toBe("[[]]");
  });

  it("changes nothing when applied twice", () => {
    const pieces = applyWikiLinks(fromDocument(documentOf([runOf("[[Beta]]")])));
    expect(samePieces(applyWikiLinks(pieces), pieces)).toBe(true);
  });
});

describe("formatting", () => {
  it("flips bold run by run over a selection", () => {
    const pieces = fromDocument(documentOf([runOf("ab", { bold: true }), runOf("cd")]));
    expect(textWhere(applyFormat(pieces, 0, 4, "bold"), (style) => style.bold)).toBe("cd");
  });

  it("decides underline by the first character and applies it to the whole selection", () => {
    const pieces = fromDocument(documentOf([runOf("ab", { underline: true }), runOf("cd")]));
    const cleared = applyFormat(pieces, 0, 4, "underline");
    expect(textWhere(cleared, (style) => style.underline)).toBe("");
    expect(textWhere(applyFormat(cleared, 0, 4, "underline"), (style) => style.underline)).toBe("abcd");
  });

  it("makes a heading bold 20 pt text without italic or code", () => {
    const style = formatStyle({ ...DEFAULT_STYLE, italic: true, code: true }, "heading", false);
    expect(style).toEqual({ ...DEFAULT_STYLE, heading: true, bold: true });
  });

  it("makes code monospaced and keeps the heading size", () => {
    const style = formatStyle({ ...DEFAULT_STYLE, bold: true, italic: true, heading: true }, "code", false);
    expect(style).toEqual({ ...DEFAULT_STYLE, code: true, heading: true });
  });

  it("returns body text to 14 pt regular and keeps underline", () => {
    const style = formatStyle({ ...DEFAULT_STYLE, heading: true, bold: true, underline: true }, "body", false);
    expect(style).toEqual({ ...DEFAULT_STYLE, underline: true });
  });

  it("toggles underline for the text typed at a collapsed caret", () => {
    expect(caretStyleAfter(DEFAULT_STYLE, "underline").underline).toBe(true);
    expect(caretStyleAfter({ ...DEFAULT_STYLE, underline: true }, "underline").underline).toBe(false);
  });
});

describe("replaceRange and typingStyle", () => {
  it("inserts at the caret and reports the caret after the new text", () => {
    const result = replaceRange(fromDocument(documentOf([runOf("ac")])), 1, 1, "b", DEFAULT_STYLE);
    expect(flatten(result.pieces)).toBe("abc");
    expect(result.caret).toBe(2);
  });

  it("makes a new paragraph for a line break", () => {
    const result = replaceRange(fromDocument(documentOf([runOf("ac")])), 1, 1, "\n", DEFAULT_STYLE);
    expect(toDocument(result.pieces).paragraphs).toHaveLength(2);
  });

  it("uses the pending toolbar style only at the caret it was chosen at", () => {
    const pieces = fromDocument(documentOf([runOf("ab", { bold: true })]));
    const pending = { offset: 2, style: DEFAULT_STYLE };
    expect(typingStyle(pieces, 2, pending)).toEqual(DEFAULT_STYLE);
    expect(typingStyle(pieces, 1, pending).bold).toBe(true);
  });
});

describe("linkTarget and wikiLinkURL", () => {
  it("names the page a wiki link points at", () => {
    expect(linkTarget("wiki://page/Buffer%20Overflows")).toBe("Buffer Overflows");
  });

  it("gives no name for other links and for an empty target", () => {
    expect(linkTarget("https://example.com/a")).toBeNull();
    expect(linkTarget("wiki://page/")).toBeNull();
  });

  it("reads back the page name it encoded", () => {
    expect(linkTarget(wikiLinkURL("Café & Tea"))).toBe("Café & Tea");
  });
});

describe("characterCount", () => {
  it("counts a letter with its combining mark as one character", () => {
    expect(characterCount("e\u0301")).toBe(1);
  });

  it("counts an emoji as one character", () => {
    expect(characterCount("😀x")).toBe(2);
  });
});
