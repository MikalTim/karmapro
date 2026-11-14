import { describe, expect, it } from "vitest";
import {
  EMPTY_HISTORY,
  canGoBack,
  canGoForward,
  historyMenuEntries,
  jumpToHistory,
  recordFile,
  stepHistory,
  type FileHistory,
} from "./history";

function historyOf(entries: string[], index: number): FileHistory {
  return { entries, index };
}

describe("recordFile", () => {
  it("records the first file and makes it current", () => {
    expect(recordFile(EMPTY_HISTORY, "/p/a.c")).toEqual({ entries: ["/p/a.c"], index: 0 });
  });

  it("records nothing when the file is already the current entry", () => {
    const before = historyOf(["/p/a.c", "/p/b.c"], 1);
    expect(recordFile(before, "/p/b.c")).toBe(before);
  });

  it("drops the forward entries when a new file is shown", () => {
    const before = historyOf(["/p/a.c", "/p/b.c", "/p/c.c"], 1);
    expect(recordFile(before, "/p/d.c")).toEqual({ entries: ["/p/a.c", "/p/b.c", "/p/d.c"], index: 2 });
  });
});

describe("back and forward", () => {
  it("steps through the entries and keeps the forward ones", () => {
    const at = historyOf(["/p/a.c", "/p/b.c"], 1);
    expect(canGoBack(at)).toBe(true);
    expect(canGoForward(at)).toBe(false);
    const back = stepHistory(at, -1);
    expect(back).toEqual({ entries: ["/p/a.c", "/p/b.c"], index: 0 });
    expect(back && canGoForward(back)).toBe(true);
    expect(back && stepHistory(back, 1)?.index).toBe(1);
  });

  it("has no step past either end", () => {
    const only = historyOf(["/p/a.c"], 0);
    expect(canGoBack(only)).toBe(false);
    expect(canGoForward(only)).toBe(false);
    expect(stepHistory(only, -1)).toBeNull();
    expect(stepHistory(only, 1)).toBeNull();
    expect(canGoBack(EMPTY_HISTORY)).toBe(false);
  });
});

describe("jumpToHistory", () => {
  it("jumps to a chosen entry and drops the entries after it", () => {
    const before = historyOf(["/p/a.c", "/p/b.c", "/p/c.c"], 2);
    expect(jumpToHistory(before, 0)).toEqual({ entries: ["/p/a.c"], index: 0 });
  });

  it("refuses an index outside the history", () => {
    expect(jumpToHistory(historyOf(["/p/a.c"], 0), 3)).toBeNull();
    expect(jumpToHistory(historyOf(["/p/a.c"], 0), -1)).toBeNull();
  });
});

describe("historyMenuEntries", () => {
  it("lists the newest file first, including forward entries", () => {
    const entries = historyMenuEntries(historyOf(["/p/src/a.c", "/p/src/b.c", "/p/src/c.c"], 0));
    expect(entries.map((entry) => entry.name)).toEqual(["c.c", "b.c", "a.c"]);
    expect(entries[0]).toEqual({ index: 2, name: "c.c", path: "/p/src/c.c" });
  });

  it("shows at most the last ten files", () => {
    const paths = Array.from({ length: 12 }, (_, i) => `/p/f${i}.c`);
    const entries = historyMenuEntries(historyOf(paths, 11));
    expect(entries).toHaveLength(10);
    expect(entries[0].index).toBe(11);
    expect(entries[9].index).toBe(2);
  });

  it("is empty before any file was opened", () => {
    expect(historyMenuEntries(EMPTY_HISTORY)).toEqual([]);
  });
});
