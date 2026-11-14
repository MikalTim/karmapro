import { describe, expect, it } from "vitest";
import { noteCellValue, noteRowKey, type NoteDTO } from "./notesModel";

const note: NoteDTO = {
  path: "/work/app/src/main.c",
  relativePath: "src/main.c",
  file: "main.c",
  line: 42,
  text: "check the bounds",
};

describe("notes rows", () => {
  it("shows the file name, the line number and the note text in their columns", () => {
    expect(noteCellValue(note, "file")).toBe("main.c");
    expect(noteCellValue(note, "line")).toBe("42");
    expect(noteCellValue(note, "text")).toBe("check the bounds");
  });

  it("shows nothing for a column the window does not have", () => {
    expect(noteCellValue(note, "path")).toBe("");
  });

  it("tells two notes on different lines of one file apart, and the same line apart from another file", () => {
    const otherLine = { ...note, line: 43 };
    const otherFile = { ...note, path: "/work/app/src/util.c" };
    expect(noteRowKey(note)).not.toBe(noteRowKey(otherLine));
    expect(noteRowKey(note)).not.toBe(noteRowKey(otherFile));
    expect(noteRowKey(note)).toBe(noteRowKey({ ...note, text: "edited" }));
  });
});
