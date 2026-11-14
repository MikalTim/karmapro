import { describe, expect, it } from "vitest";
import { ApiError } from "../../../lib/api";
import {
  bugCellValue,
  bugDetailBody,
  bugDetailMeta,
  buildBugInput,
  formFromBug,
  isNeedsPasswordError,
  newBugForm,
  passwordOrNull,
  passwordsMatch,
  presetFill,
  selectionAfterReload,
  severityColor,
  backupSavedText,
  type BugChoicesDTO,
  type BugDTO,
  type BugInput,
} from "./bugModel";

// The defaults and presets have the shape `BugService.choices()` returns.
const choices: BugChoicesDTO = {
  severities: ["info", "low", "medium", "high", "critical"],
  statuses: ["Open", "In Progress", "Resolved"],
  presets: [
    { title: "Buffer overflow", description: "Unchecked copy into a fixed buffer." },
    { title: "Hard-coded secret", description: null },
  ],
  defaults: {
    title: "",
    severity: "info",
    exploitability: "info",
    detail: "",
    packageName: "",
    version: "",
    status: "Open",
  },
};

function bug(overrides: Partial<BugDTO> = {}): BugDTO {
  return {
    id: "3f2a9c10-aaaa-bbbb-cccc-000000000001",
    title: "Heap overflow in parser",
    severity: "high",
    exploitability: "low",
    detail: "Details here",
    packageName: "libparse",
    version: "1.2",
    status: "Open",
    createdAt: "2026-01-02T03:04:05Z",
    createdText: "Jan 2, 2026 03:04",
    shortID: "3f2a9c10",
    packageText: "libparse v1.2",
    filePath: null,
    line: null,
    ...overrides,
  };
}

const form: BugInput = { ...choices.defaults, title: "T" };

describe("list cells and detail", () => {
  it("shows the eight-character id and the package text in their columns", () => {
    const row = bug();
    expect(bugCellValue(row, "id")).toBe("3f2a9c10");
    expect(bugCellValue(row, "package")).toBe("libparse v1.2");
    expect(bugCellValue(row, "created")).toBe("Jan 2, 2026 03:04");
  });

  it("shows nothing for a column it does not know", () => {
    expect(bugCellValue(bug(), "unknown")).toBe("");
  });

  it("colours severity levels and leaves other levels in the secondary label colour", () => {
    expect(severityColor("critical")).toBe("var(--system-red)");
    expect(severityColor("high")).toBe("var(--system-orange)");
    expect(severityColor("medium")).toBe("var(--system-yellow)");
    expect(severityColor("low")).toBe("var(--system-green)");
    expect(severityColor("info")).toBe("var(--secondary-label)");
  });

  it("lists the package with its version on a second line only when both exist", () => {
    expect(bugDetailMeta(bug())).toBe(
      "Severity: high   ·   Exploitability: low   ·   Status: Open\nCreated: Jan 2, 2026 03:04\nPackage: libparse   v1.2",
    );
    expect(bugDetailMeta(bug({ packageName: "", version: "", packageText: "—" }))).toBe(
      "Severity: high   ·   Exploitability: low   ·   Status: Open\nCreated: Jan 2, 2026 03:04",
    );
  });

  it("says when a report has no description", () => {
    expect(bugDetailBody(bug({ detail: "" }))).toBe("(no description)");
    expect(bugDetailBody(bug({ detail: "x" }))).toBe("x");
  });
});

describe("editor validation and defaults", () => {
  it("starts a new report from the server defaults", () => {
    expect(newBugForm(choices.defaults)).toEqual({
      title: "",
      severity: "info",
      exploitability: "info",
      detail: "",
      packageName: "",
      version: "",
      status: "Open",
    });
  });

  it("requires a title once surrounding whitespace is trimmed", () => {
    expect(buildBugInput({ ...form, title: "   \n " })).toEqual({ error: "A title is required." });
  });

  it("trims the title, package and version, but keeps the description as typed", () => {
    const built = buildBugInput({
      ...form,
      title: "  Overflow  ",
      packageName: " libparse ",
      version: " 1.2 ",
      detail: "  line one\n  line two  ",
    });
    expect(built).toEqual({
      input: {
        title: "Overflow",
        severity: "info",
        exploitability: "info",
        detail: "  line one\n  line two  ",
        packageName: "libparse",
        version: "1.2",
        status: "Open",
      },
    });
  });

  it("populates the editor from a saved report", () => {
    const populated = formFromBug(bug());
    expect(populated.title).toBe("Heap overflow in parser");
    expect(populated.severity).toBe("high");
    expect(populated.packageName).toBe("libparse");
  });
});

describe("preset titles", () => {
  it("fills nothing for the Custom title item", () => {
    expect(presetFill(choices.presets, 0)).toBeNull();
  });

  it("fills the title and description of the chosen preset", () => {
    expect(presetFill(choices.presets, 1)).toEqual({
      title: "Buffer overflow",
      description: "Unchecked copy into a fixed buffer.",
    });
  });

  it("keeps the description when the preset has none", () => {
    expect(presetFill(choices.presets, 2)).toEqual({ title: "Hard-coded secret", description: null });
  });

  it("fills nothing for an index past the presets", () => {
    expect(presetFill(choices.presets, 9)).toBeNull();
  });
});

describe("password handling", () => {
  it("asks for a password only on a 422 that carries needsPassword", () => {
    expect(isNeedsPasswordError(new ApiError(422, "encrypted", { error: "encrypted", needsPassword: true }))).toBe(true);
    expect(isNeedsPasswordError(new ApiError(422, "other", { error: "other" }))).toBe(false);
    expect(isNeedsPasswordError(new ApiError(400, "wrong", { error: "wrong", needsPassword: true }))).toBe(false);
    expect(isNeedsPasswordError(new Error("network"))).toBe(false);
  });

  it("reads a cancelled or blank prompt as no password", () => {
    expect(passwordOrNull({ button: 1, values: ["secret"] })).toBeNull();
    expect(passwordOrNull({ button: 0, values: [""] })).toBeNull();
    expect(passwordOrNull({ button: 0, values: ["  pass  "] })).toBe("  pass  ");
  });

  it("accepts a backup only when both entries are present and equal", () => {
    expect(passwordsMatch("abc", "abc")).toBe(true);
    expect(passwordsMatch("abc", "abd")).toBe(false);
    expect(passwordsMatch("abc", null)).toBe(false);
    expect(passwordsMatch(null, null)).toBe(false);
  });

  it("says whether the saved backup is protected", () => {
    expect(backupSavedText(3, "KarmaProBugBackup.karmapro", false)).toBe(
      "Exported 3 bug reports to KarmaProBugBackup.karmapro.",
    );
    expect(backupSavedText(1, "b.karmapro", true)).toBe(
      "Exported 1 bug reports to b.karmapro.\nThis backup is password protected.",
    );
  });
});

describe("selection after a reload", () => {
  const first = bug({ id: "id-a" });
  const second = bug({ id: "id-b" });
  const third = bug({ id: "id-c" });

  it("keeps the selected row index, so the report now in that row is selected", () => {
    expect(selectionAfterReload([first, second, third], [first, third], second.id)).toBe(third.id);
  });

  it("selects the report now in the same row after a search", () => {
    expect(selectionAfterReload([first, second, third], [third, first], second.id)).toBe(first.id);
  });

  it("selects nothing when the row no longer exists", () => {
    expect(selectionAfterReload([first, second, third], [first], third.id)).toBeNull();
  });

  it("selects nothing without a selection", () => {
    expect(selectionAfterReload([first], [first], null)).toBeNull();
  });
});
