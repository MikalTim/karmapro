import { describe, expect, it } from "vitest";
import { DEFAULT_STYLE, type TextStyle } from "../richText";
import {
  deletionRange,
  diffText,
  editorWindowKey,
  errorMessage,
  externalHref,
  isSaveShortcut,
  linkFromFields,
  normalizePastedText,
  selectionLinkText,
  statusLine,
  styleClasses,
} from "./editorModel";

describe("styleClasses", () => {
  it("draws nothing for plain text", () => {
    expect(styleClasses(DEFAULT_STYLE)).toEqual([]);
  });

  it("lists every style the run carries", () => {
    const style: TextStyle = { ...DEFAULT_STYLE, bold: true, heading: true, dim: true, link: "wiki://page/Beta" };
    expect(styleClasses(style)).toEqual(["wiki-bold", "wiki-heading", "wiki-dim", "wiki-link"]);
  });
});

describe("diffText", () => {
  it("finds nothing when the text is unchanged", () => {
    expect(diffText("abc", "abc")).toBeNull();
  });

  it("finds an insertion", () => {
    expect(diffText("abcd", "abXYcd")).toEqual({ start: 2, oldEnd: 2, inserted: "XY" });
  });

  it("finds a deletion", () => {
    expect(diffText("abXYcd", "abcd")).toEqual({ start: 2, oldEnd: 4, inserted: "" });
  });

  it("finds a replacement", () => {
    expect(diffText("hello", "help")).toEqual({ start: 3, oldEnd: 5, inserted: "p" });
  });

  it("keeps an emoji whole", () => {
    expect(diffText("a😀b", "a😁b")).toEqual({ start: 1, oldEnd: 3, inserted: "😁" });
  });
});

describe("deletionRange", () => {
  it("removes a character together with its combining mark", () => {
    expect(deletionRange("cafe\u0301", { start: 5, end: 5 }, "backward", "character")).toEqual({ start: 3, end: 5 });
  });

  it("removes the character after the caret on Delete", () => {
    expect(deletionRange("abc", { start: 0, end: 0 }, "forward", "character")).toEqual({ start: 0, end: 1 });
  });

  it("does nothing at the start of the page", () => {
    expect(deletionRange("abc", { start: 0, end: 0 }, "backward", "character")).toEqual({ start: 0, end: 0 });
  });

  it("removes a selection whole", () => {
    expect(deletionRange("abc", { start: 1, end: 2 }, "backward", "character")).toEqual({ start: 1, end: 2 });
  });

  it("removes the word before the caret with the spaces after it", () => {
    expect(deletionRange("hello world", { start: 6, end: 6 }, "backward", "word")).toEqual({ start: 0, end: 6 });
  });

  it("removes the rest of the word after the caret", () => {
    expect(deletionRange("hello world", { start: 3, end: 3 }, "forward", "word")).toEqual({ start: 3, end: 5 });
  });
});

describe("linkFromFields", () => {
  it("uses the link text as the page when no page is given", () => {
    expect(linkFromFields("Buffer Notes", "")).toEqual({ text: "Buffer Notes", pageName: "Buffer Notes" });
  });

  it("uses the page as the link text when no text is given", () => {
    expect(linkFromFields("", "Buffer Overflows")).toEqual({ text: "Buffer Overflows", pageName: "Buffer Overflows" });
  });

  it("trims both fields", () => {
    expect(linkFromFields("  See  ", " Beta ")).toEqual({ text: "See", pageName: "Beta" });
  });

  it("does nothing when both fields are blank", () => {
    expect(linkFromFields("", "  ")).toBeNull();
  });
});

describe("selectionLinkText", () => {
  it("trims the selected words", () => {
    expect(selectionLinkText("  Beta ")).toBe("Beta");
  });

  it("gives no link for a blank selection", () => {
    expect(selectionLinkText("   ")).toBeNull();
  });
});

describe("statusLine", () => {
  it("reads Saved when nothing is pending", () => {
    expect(statusLine(false, "Alpha", 5)).toBe("Saved — Alpha · 5 characters");
  });

  it("reads Edited while changes are pending", () => {
    expect(statusLine(true, "Alpha", 0)).toBe("Edited — Alpha · 0 characters");
  });
});

describe("externalHref", () => {
  it("keeps http and https addresses", () => {
    expect(externalHref("https://example.com/a")).toBe("https://example.com/a");
  });

  it("refuses other schemes and wiki links", () => {
    expect(externalHref("javascript:alert(1)")).toBeNull();
    expect(externalHref("wiki://page/Beta")).toBeNull();
    expect(externalHref("not a url")).toBeNull();
  });
});

describe("isSaveShortcut", () => {
  it("uses Command on macOS", () => {
    expect(isSaveShortcut("s", true, false, true)).toBe(true);
    expect(isSaveShortcut("s", false, true, true)).toBe(false);
  });

  it("uses Control elsewhere", () => {
    expect(isSaveShortcut("s", false, true, false)).toBe(true);
    expect(isSaveShortcut("S", true, false, false)).toBe(false);
  });

  it("ignores other keys", () => {
    expect(isSaveShortcut("d", true, false, true)).toBe(false);
  });
});

describe("normalizePastedText", () => {
  it("turns every line ending into a paragraph break", () => {
    expect(normalizePastedText("a\r\nb\rc\nd")).toBe("a\nb\nc\nd");
  });
});

describe("editorWindowKey and errorMessage", () => {
  it("keys the editor by page", () => {
    expect(editorWindowKey("alpha")).toBe("WikiEditorWindow:alpha");
  });

  it("reads the message of an error and stringifies anything else", () => {
    expect(errorMessage(new Error("boom"))).toBe("boom");
    expect(errorMessage("plain")).toBe("plain");
  });
});
