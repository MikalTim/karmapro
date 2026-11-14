import { describe, expect, it } from "vitest";
import { changesPickerItems, isHighlighted, NO_CHANGES_VALUE } from "./diffLines";
import type { PRChanges, PRChangedFile, PRDiffLine } from "./prTypes";

function file(path: string, title: string): PRChangedFile {
  return { path, absolutePath: `/tmp/review/${path}`, title, summary: "+1  \u22121", lines: [] };
}

function changes(files: PRChangedFile[]): PRChanges {
  return {
    windowTitle: "Pull Request Changes",
    files,
    emptyTitle: "No reviewable changes",
    emptyMessage: "This pull request has no reviewable file changes.",
  };
}

function line(kind: PRDiffLine["kind"], suspicious: boolean): PRDiffLine {
  return { text: "x", kind, suspicious };
}

describe("changesPickerItems", () => {
  it("has one entry per changed file, valued by its position", () => {
    const items = changesPickerItems(changes([file("src/a.c", "M  src/a.c"), file("src/b.c", "A  src/b.c (added)")]));

    expect(items).toEqual([
      { title: "M  src/a.c", value: "0" },
      { title: "A  src/b.c (added)", value: "1" },
    ]);
  });

  it("shows only the empty entry when nothing can be reviewed", () => {
    expect(changesPickerItems(changes([]))).toEqual([{ title: "No reviewable changes", value: NO_CHANGES_VALUE }]);
  });
});

describe("isHighlighted", () => {
  it("highlights an added line the heuristic flags", () => {
    expect(isHighlighted(line("added", true))).toBe(true);
  });

  it("does not highlight an unflagged added line", () => {
    expect(isHighlighted(line("added", false))).toBe(false);
  });

  it("does not highlight a removed line, even one that was flagged", () => {
    expect(isHighlighted(line("removed", true))).toBe(false);
  });
});
