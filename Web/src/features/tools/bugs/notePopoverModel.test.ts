import { describe, expect, it } from "vitest";
import { anchorRect, fileNameOf, noteHeading, noteSaveAction, removeIsOffered } from "./notePopoverModel";

describe("note popover", () => {
  it("titles the popover with the line, using an em dash", () => {
    expect(noteHeading(6)).toBe("Note — Line 6");
  });

  it("names the file by its last path component", () => {
    expect(fileNameOf("/work/app/src/main.c")).toBe("main.c");
    expect(fileNameOf("main.c")).toBe("main.c");
  });

  it("removes the note when the text is blank once trimmed", () => {
    expect(noteSaveAction("")).toEqual({ kind: "remove" });
    expect(noteSaveAction("  \n\t ")).toEqual({ kind: "remove" });
  });

  it("saves non-blank text exactly as typed, without trimming", () => {
    expect(noteSaveAction("  check this\n")).toEqual({ kind: "save", text: "  check this\n" });
  });

  it("offers Remove only when the line already had a note", () => {
    expect(removeIsOffered("check")).toBe(true);
    expect(removeIsOffered(null)).toBe(false);
  });

  it("points at a DOMRect as given and at a bare point with zero size", () => {
    expect(anchorRect({ x: 10, y: 20, width: 30, height: 14 })).toEqual({ x: 10, y: 20, width: 30, height: 14 });
    expect(anchorRect({ x: 10, y: 20 })).toEqual({ x: 10, y: 20, width: 0, height: 0 });
  });
});
