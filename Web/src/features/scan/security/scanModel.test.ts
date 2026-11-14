import { describe, expect, it } from "vitest";
import {
  COLUMNS,
  EMPTY_STATE,
  cellFor,
  closeCancel,
  errorText,
  findingText,
  levelColor,
  nextSort,
  pendingNotice,
  rowAt,
  statusParts,
  triageLook,
  visibleColumns,
  type FindingDTO,
  type NoticeDTO,
} from "./scanModel";

function finding(overrides: Partial<FindingDTO> = {}): FindingDTO {
  return {
    key: "/p/vuln.c#6",
    path: "/p/src/vuln.c",
    displayPath: "src/vuln.c",
    line: 6,
    function: "main",
    category: "Buffer Overflow",
    message: "strcpy into a fixed buffer",
    taintPath: null,
    severity: "High",
    severityRank: 2,
    exploitability: "Critical",
    exploitabilityRank: 3,
    reachable: true,
    crossFile: false,
    engine: "AST",
    awareness: null,
    triage: null,
    ...overrides,
  };
}

function ids(columns: { id: string }[]): string[] {
  return columns.map((column) => column.id);
}

describe("visibleColumns", () => {
  it("shows the eight scan columns and the Finding column by default", () => {
    expect(ids(visibleColumns(EMPTY_STATE))).toEqual(["exp", "sev", "cat", "fn", "file", "line", "src", "crossfile", "msg"]);
  });

  it("adds In PR? and Triage in table order when the window asks for them", () => {
    const shown = visibleColumns({ showPullRequestColumn: true, showTriageColumn: true });
    expect(ids(shown)).toEqual(["exp", "sev", "cat", "fn", "file", "line", "src", "crossfile", "inpr", "triage", "msg"]);
    expect(shown.find((column) => column.id === "inpr")?.title).toBe("In PR?");
  });
});

describe("sorting", () => {
  it("maps every sortable column to the server's sort key and first-click direction", () => {
    const sortable = COLUMNS.filter((column) => column.sort).map((column) => [column.id, column.sort?.key, column.sort?.ascending]);
    expect(sortable).toEqual([
      ["exp", "exploitability", false],
      ["sev", "severity", false],
      ["cat", "category", true],
      ["fn", "function", true],
      ["file", "fileURL", true],
      ["line", "line", true],
      ["src", "scanningSource", true],
      ["crossfile", "crossFile", false],
      ["inpr", "inpr", true],
    ]);
  });

  it("leaves the Triage and Finding columns unsortable", () => {
    expect(COLUMNS.find((column) => column.id === "triage")?.sort).toBeUndefined();
    expect(COLUMNS.find((column) => column.id === "msg")?.sort).toBeUndefined();
  });

  it("sorts a new column in its prototype direction and reverses the sorted one", () => {
    const severity = { key: "severity", ascending: false };
    expect(nextSort(null, severity)).toEqual({ key: "severity", ascending: false });
    expect(nextSort({ key: "severity", ascending: false }, severity)).toEqual({ key: "severity", ascending: true });
    expect(nextSort({ key: "line", ascending: true }, severity)).toEqual({ key: "severity", ascending: false });
  });

  it("does not change the prototype when it reverses a sort", () => {
    const prototype = { key: "line", ascending: true };
    nextSort({ key: "line", ascending: true }, prototype);
    expect(prototype).toEqual({ key: "line", ascending: true });
  });
});

describe("severity and exploitability colours", () => {
  it("colours critical red, high orange, medium yellow and low gray", () => {
    expect([3, 2, 1, 0].map(levelColor)).toEqual([
      "var(--system-red)",
      "var(--system-orange)",
      "var(--system-yellow)",
      "var(--system-gray)",
    ]);
  });

  it("colours the Exploitability and Severity cells by their own ranks", () => {
    const row = finding({ exploitability: "Low", exploitabilityRank: 0, severity: "Critical", severityRank: 3 });
    expect(cellFor(row, "exp").parts[0]).toMatchObject({ text: "Low", color: "var(--system-gray)", weight: 700 });
    expect(cellFor(row, "sev").parts[0]).toMatchObject({ text: "Critical", color: "var(--system-red)", weight: 600 });
  });
});

describe("cell text", () => {
  it("marks an unreachable function with the arrow and says so in the tooltip", () => {
    const unreachable = cellFor(finding({ reachable: false }), "fn");
    expect(unreachable.parts[0].text).toBe("main  \u21E2");
    expect(unreachable.tooltip).toBe("Function is NOT reachable from an entry point in this file.");
    expect(cellFor(finding(), "fn")).toEqual({
      parts: [expect.objectContaining({ text: "main" })],
      tooltip: "Function is reachable from an entry point.",
    });
  });

  it("shows the base line number of a fixed finding in secondary colour", () => {
    const fixed = cellFor(finding({ line: 12, awareness: "fixed" }), "line");
    expect(fixed.parts[0]).toMatchObject({ text: "12 (base)", color: "var(--secondary-label)" });
    expect(fixed.tooltip).toBe("Line 12 of the base revision, not of the current file.");
    expect(cellFor(finding({ line: 12 }), "line").parts[0].text).toBe("12");
  });

  it("shows the file path relative to the scanned folder, with the full path as tooltip", () => {
    expect(cellFor(finding(), "file")).toEqual({ parts: [expect.objectContaining({ text: "src/vuln.c" })], tooltip: "/p/src/vuln.c" });
  });

  it("colours each engine in a row that several engines reported", () => {
    const row = cellFor(finding({ engine: "AST, AI" }), "src");
    expect(row.parts.map((part) => part.text)).toEqual(["AST", ", ", "AI"]);
    expect(row.parts[0]).toMatchObject({ color: "var(--system-green)", weight: 700 });
    expect(row.parts[1]).toMatchObject({ color: "var(--label)", weight: 400 });
    expect(row.parts[2]).toMatchObject({ color: "var(--system-purple)", weight: 700 });
    expect(row.tooltip).toBe("Reported by AST, AI.");
  });

  it("explains an AI-only finding and colours a heuristic engine blue", () => {
    expect(cellFor(finding({ engine: "AI" }), "src").tooltip).toBe(
      "Found by the AI assistant model during the AI deep scan phase.",
    );
    const heuristic = cellFor(finding({ engine: "Heuristic" }), "src");
    expect(heuristic).toEqual({ parts: [expect.objectContaining({ color: "var(--system-blue)", weight: 600 })], tooltip: null });
  });

  it("says Yes in orange for cross-file taint and No otherwise", () => {
    expect(cellFor(finding({ crossFile: true }), "crossfile").parts[0]).toMatchObject({
      text: "Yes",
      color: "var(--system-orange)",
      weight: 600,
    });
    expect(cellFor(finding(), "crossfile").parts[0].text).toBe("No");
  });

  it("names the pull request awareness of each finding and leaves unclassified rows empty", () => {
    expect(cellFor(finding({ awareness: "introduced" }), "inpr").parts[0]).toMatchObject({ text: "New", color: "var(--system-red)", weight: 700 });
    expect(cellFor(finding({ awareness: "contextual" }), "inpr").parts[0]).toMatchObject({ text: "Touched", color: "var(--system-orange)" });
    expect(cellFor(finding({ awareness: "preExisting" }), "inpr").parts[0]).toMatchObject({ text: "Pre-existing", color: "var(--secondary-label)" });
    expect(cellFor(finding({ awareness: "fixed" }), "inpr").parts[0]).toMatchObject({ text: "Fixed", color: "var(--system-green)" });
    expect(cellFor(finding({ awareness: null }), "inpr").parts[0].text).toBe("");
  });

  it("marks AI triage verdicts with a check or a cross, and leaves unchecked rows empty", () => {
    expect(cellFor(finding({ triage: true }), "triage").parts[0]).toMatchObject({ text: "\u2713", color: "var(--system-red)", size: 14 });
    expect(cellFor(finding({ triage: true }), "triage").tooltip).toBe("AI triage: the model judges this a valid issue.");
    expect(cellFor(finding({ triage: false }), "triage").parts[0]).toMatchObject({ text: "\u2717", color: "var(--secondary-label)" });
    expect(cellFor(finding(), "triage").parts[0].text).toBe("");
  });
});

describe("Finding column text", () => {
  it("is the message alone for a plain reachable finding", () => {
    expect(findingText(finding())).toBe("strcpy into a fixed buffer");
  });

  it("adds the taint flow, the AI prefix and the unreachable note, in that order", () => {
    const row = finding({ engine: "AI", taintPath: "argv[1] \u2192 buf", message: "overflow", reachable: false });
    expect(findingText(row)).toBe("flow: argv[1] \u2192 buf\nflow: overflow\n(function not reachable from entry point)");
    expect(cellFor(row, "msg").tooltip).toBe(findingText(row));
  });

  it("does not add the AI prefix when AI is one engine among several", () => {
    expect(findingText(finding({ engine: "AST, AI", message: "overflow" }))).toBe("overflow");
  });
});

describe("status line", () => {
  it("draws the AI phase prefix in bold purple and the rest in green", () => {
    const parts = statusParts({ status: "AI phase: reviewing the code\u2026", statusIsAIPhase: true });
    expect(parts).toEqual([
      expect.objectContaining({ text: "AI phase: ", color: "var(--system-purple)", weight: 700 }),
      expect.objectContaining({ text: "reviewing the code\u2026", color: "var(--system-green)", weight: 400 }),
    ]);
  });

  it("draws any other status in secondary colour", () => {
    expect(statusParts({ status: "Scan complete: no issues found.", statusIsAIPhase: false })).toEqual([
      expect.objectContaining({ text: "Scan complete: no issues found.", color: "var(--secondary-label)" }),
    ]);
  });
});

describe("buttons", () => {
  it("fills the Triage (AI) button purple when it can run and fades a gray one otherwise", () => {
    expect(triageLook(true)).toEqual({ background: "var(--system-purple)", opacity: 1 });
    expect(triageLook(false)).toEqual({ background: "var(--system-gray)", opacity: 0.6 });
  });

  it("finds the selected finding only while its row exists", () => {
    const rows = [finding({ key: "a#1" }), finding({ key: "b#2" })];
    expect(rowAt(rows, null)).toBeNull();
    expect(rowAt(rows, 1)?.key).toBe("b#2");
    expect(rowAt(rows, 2)).toBeNull();
    expect(rowAt(rows, -1)).toBeNull();
  });
});

describe("closing the window", () => {
  it("stops a plain scan that is running", () => {
    expect(closeCancel({ showPullRequestColumn: false, canRescan: false, triageRunning: false })).toBe("cancelScan");
  });

  it("stops a plain triage that is running, which also disables Rescan", () => {
    expect(closeCancel({ showPullRequestColumn: false, canRescan: false, triageRunning: true })).toBe("cancelScan");
  });

  it("stops nothing when the window is idle", () => {
    expect(closeCancel({ showPullRequestColumn: false, canRescan: true, triageRunning: false })).toBeNull();
  });

  it("keeps a pull request scan running and stops only its triage", () => {
    expect(closeCancel({ showPullRequestColumn: true, canRescan: false, triageRunning: false })).toBeNull();
    expect(closeCancel({ showPullRequestColumn: true, canRescan: false, triageRunning: true })).toBe("cancelTriage");
  });
});

describe("notices", () => {
  const notice: NoticeDTO = { id: 2, title: "AI scan unavailable", message: "Connect a model." };

  it("shows a notice once, when its id is newer than the last one shown", () => {
    expect(pendingNotice(notice, 1)).toEqual(notice);
    expect(pendingNotice(notice, 2)).toBeNull();
  });

  it("does not show a notice that was already there before the page started", () => {
    expect(pendingNotice(notice, null)).toBeNull();
    expect(pendingNotice(null, 1)).toBeNull();
  });
});

describe("errorText", () => {
  it("uses the message of an error and the text of anything else", () => {
    expect(errorText(new Error("There are no findings to export."))).toBe("There are no findings to export.");
    expect(errorText("plain")).toBe("plain");
  });
});
