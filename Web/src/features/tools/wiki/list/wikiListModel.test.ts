import { describe, expect, it } from "vitest";
import { ApiError } from "../../../../lib/api";
import {
  backupSavedText,
  collectConflictDecisions,
  conflictInformativeText,
  deleteConfirmText,
  needsPasswordAnswer,
  passwordOrNull,
  passwordsMatch,
  renamedTitle,
  selectionAfterReload,
  wikiCellValue,
  type WikiPageDTO,
} from "./wikiListModel";

const alpha: WikiPageDTO = {
  slug: "alpha",
  title: "Alpha",
  created: 1,
  updated: 2,
  createdText: "Nov 1, 2026, 9:00 AM",
  updatedText: "Nov 2, 2026, 10:30 AM",
};
const beta: WikiPageDTO = { ...alpha, slug: "beta", title: "Beta" };

describe("table cells", () => {
  it("shows the title and the server's date texts", () => {
    expect(wikiCellValue(alpha, "title")).toBe("Alpha");
    expect(wikiCellValue(alpha, "created")).toBe("Nov 1, 2026, 9:00 AM");
    expect(wikiCellValue(alpha, "updated")).toBe("Nov 2, 2026, 10:30 AM");
  });

  it("shows nothing for an unknown column", () => {
    expect(wikiCellValue(alpha, "slug")).toBe("");
  });
});

describe("rename", () => {
  it("sends a new title", () => {
    expect(renamedTitle("Alpha", "Gamma")).toBe("Gamma");
  });

  it("changes nothing when cancelled, blank or unchanged", () => {
    expect(renamedTitle("Alpha", null)).toBeNull();
    expect(renamedTitle("Alpha", "   ")).toBeNull();
    expect(renamedTitle("Alpha", "Alpha")).toBeNull();
  });
});

describe("selection after a reload", () => {
  it("keeps the selection while the page is still listed", () => {
    expect(selectionAfterReload([alpha, beta], "beta")).toBe("beta");
  });

  it("drops the selection when the page is no longer listed", () => {
    expect(selectionAfterReload([alpha], "beta")).toBeNull();
    expect(selectionAfterReload([alpha], null)).toBeNull();
  });
});

describe("alert texts", () => {
  it("builds the delete confirmation", () => {
    expect(deleteConfirmText("Alpha")).toBe('Delete "Alpha" permanently? This cannot be undone.');
  });

  it("builds the backup saved text with the page count and the protection note", () => {
    expect(backupSavedText(1, "KarmaProWiki.karmawiki", false)).toBe("Exported 1 page to KarmaProWiki.karmawiki.");
    expect(backupSavedText(3, "b.karmawiki", true)).toBe(
      "Exported 3 pages to b.karmawiki.\nThis backup is password protected.",
    );
  });

  it("builds the conflict question for a page", () => {
    expect(conflictInformativeText("Alpha")).toBe(
      '"Alpha" already exists in your wiki. What should happen to the imported copy?',
    );
  });
});

describe("import conflict decisions", () => {
  it("collects one answer per conflicting page, in order", async () => {
    const asked: string[] = [];
    const answers = [0, 1, 2];
    const decisions = await collectConflictDecisions(["a", "b", "c"], async (slug) => {
      asked.push(slug);
      return answers.shift() ?? 2;
    });
    expect(asked).toEqual(["a", "b", "c"]);
    expect(decisions).toEqual({ a: "overwrite", b: "rename", c: "skip" });
  });

  it("Cancel Import skips the page and every page after it without asking again", async () => {
    const asked: string[] = [];
    const decisions = await collectConflictDecisions(["a", "b", "c"], async (slug) => {
      asked.push(slug);
      return slug === "b" ? 3 : 0;
    });
    expect(asked).toEqual(["a", "b"]);
    expect(decisions).toEqual({ a: "overwrite", b: "skip", c: "skip" });
  });

  it("asks nothing when there are no conflicts", async () => {
    const decisions = await collectConflictDecisions([], async () => {
      throw new Error("no question expected");
    });
    expect(decisions).toEqual({});
  });
});

describe("passwords", () => {
  it("returns the typed password, or null when cancelled or blank", () => {
    expect(passwordOrNull({ button: 0, values: ["secret"] })).toBe("secret");
    expect(passwordOrNull({ button: 0, values: [""] })).toBeNull();
    expect(passwordOrNull({ button: 1, values: ["secret"] })).toBeNull();
  });

  it("accepts the confirmation only when both prompts gave the same password", () => {
    expect(passwordsMatch("a", "a")).toBe(true);
    expect(passwordsMatch("a", "b")).toBe(false);
    expect(passwordsMatch(null, null)).toBe(false);
    expect(passwordsMatch("a", null)).toBe(false);
  });

  it("recognises the 422 answer that asks for a password", () => {
    expect(needsPasswordAnswer(new ApiError(422, "encrypted", { error: "encrypted", needsPassword: true }))).toBe(true);
    expect(needsPasswordAnswer(new ApiError(400, "wrong", { error: "wrong" }))).toBe(false);
    expect(needsPasswordAnswer(new Error("network"))).toBe(false);
  });
});
