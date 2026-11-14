import { describe, expect, it } from "vitest";
import {
  beginRunView,
  failedRunView,
  keepSelectionIndex,
  nextPackageSort,
  packageCellTitle,
  packageColumns,
  packageFilesText,
  packageRows,
  severityStyle,
  toneColor,
  vulnerabilityQuestion,
  type PackageFinding,
  type PackageRow,
  type PackageScanState,
} from "./packageModel";

function finding(overrides: Partial<PackageFinding> = {}): PackageFinding {
  return {
    key: "key-1",
    path: "/project/requirements.txt",
    file: "requirements.txt",
    package: "requests@2.19.0",
    severity: "high",
    severityLabel: "High",
    line: 3,
    message: "GHSA-0001 Header injection",
    ...overrides,
  };
}

function state(overrides: Partial<PackageScanState> = {}): PackageScanState {
  return {
    descriptionText: "",
    apiSources: [],
    selectedApiSource: "https://api.osv.dev/v1/querybatch",
    privacyNote: "",
    files: [],
    findings: [],
    statusText: "3 package entries in 1 file. Click Scan to query.",
    statusTone: "secondary",
    busy: false,
    progress: null,
    scanEnabled: true,
    exportEnabled: false,
    sortKey: null,
    sortAscending: true,
    ...overrides,
  };
}

function row(id: string): PackageRow {
  return { id, finding: finding({ key: id }) };
}

describe("packageRows", () => {
  it("keeps the findings' order and gives repeated ignore keys distinct row ids", () => {
    const rows = packageRows([finding({ key: "a" }), finding({ key: "b" }), finding({ key: "a" })]);
    expect(rows.map((r) => r.id)).toEqual(["a", "b", "a#1"]);
    expect(rows[2].finding.key).toBe("a");
  });
});

describe("packageColumns", () => {
  it("lets the Finding column take the width the other columns leave", () => {
    const message = packageColumns(1000).find((column) => column.id === "msg");
    // 84 + 200 + 160 + 50 for the other columns, and 2 for the table border.
    expect(message?.width).toBe(1000 - 84 - 200 - 160 - 50 - 2);
  });

  it("never makes the Finding column narrower than 320", () => {
    const message = packageColumns(200).find((column) => column.id === "msg");
    expect(message?.width).toBe(320);
  });

  it("uses the AppKit sort keys, and only Finding is not sortable", () => {
    const keys = Object.fromEntries(packageColumns(0).map((column) => [column.id, column.sortKey]));
    expect(keys).toEqual({ sev: "severity", pkg: "package", file: "fileURL", line: "line", msg: undefined });
  });

  it("right-aligns the Line column", () => {
    expect(packageColumns(0).find((column) => column.id === "line")?.align).toBe("right");
  });
});

describe("nextPackageSort", () => {
  it("sorts severity descending on its first click, as its AppKit sort descriptor does", () => {
    expect(nextPackageSort({ sortKey: null }, "severity", true)).toEqual({ key: "severity", ascending: false });
  });

  it("keeps the table's toggle for a second click on the same column", () => {
    expect(nextPackageSort({ sortKey: "severity" }, "severity", true)).toEqual({ key: "severity", ascending: true });
  });

  it("sorts other columns ascending on their first click", () => {
    expect(nextPackageSort({ sortKey: "severity" }, "package", true)).toEqual({ key: "package", ascending: true });
  });
});

describe("keepSelectionIndex", () => {
  it("keeps the row at the same index selected after the rows change", () => {
    const previous = [row("a"), row("b"), row("c")];
    expect(keepSelectionIndex(previous, "b", [row("a"), row("c")])).toBe("c");
  });

  it("clears the selection when the index is past the last row", () => {
    expect(keepSelectionIndex([row("a"), row("b")], "b", [row("a")])).toBeNull();
  });

  it("keeps no selection when none was selected", () => {
    expect(keepSelectionIndex([row("a")], null, [row("a")])).toBeNull();
  });
});

describe("beginRunView", () => {
  it("shows the detecting status, disables Scan and resets the progress", () => {
    const running = beginRunView(state({ progress: 0.4, statusText: "Done", statusTone: "error" }));
    expect(running).toMatchObject({
      busy: true,
      scanEnabled: false,
      progress: null,
      statusText: "Detecting package files…",
      statusTone: "secondary",
    });
  });
});

describe("failedRunView", () => {
  it("reports the failure in red and enables Scan again only when files were detected", () => {
    const withFiles = failedRunView(state({ files: [{ path: "/p/a", relativePath: "a", language: "Python", ecosystem: "PyPI", isLockfile: false, kind: "manifest", label: "a" }] }), "boom");
    expect(withFiles).toMatchObject({ busy: false, scanEnabled: true, statusText: "Scan failed: boom", statusTone: "error" });
    expect(failedRunView(state(), "boom").scanEnabled).toBe(false);
  });
});

describe("packageFilesText", () => {
  const file = { path: "/p/a", relativePath: "a", language: "Python", ecosystem: "PyPI", isLockfile: true, kind: "lockfile", label: "a — Python/PyPI (lockfile)" };

  it("lists one label per detected file", () => {
    const text = packageFilesText(state({ files: [file, { ...file, label: "b" }] }));
    expect(text).toBe("a — Python/PyPI (lockfile)\nb");
  });

  it("shows the placeholder once a detection found no supported files", () => {
    expect(packageFilesText(state({ statusTone: "warning" }))).toBe(
      "(no supported dependency manifests or lockfiles found)",
    );
  });

  it("shows nothing while a detection is running or before the first one", () => {
    expect(packageFilesText(state({ statusTone: "warning", busy: true }))).toBe("");
    expect(packageFilesText(state())).toBe("");
  });
});

describe("packageCellTitle", () => {
  it("shows the full path, package and message as tooltips, and none for severity and line", () => {
    const f = finding();
    expect(packageCellTitle(f, "file")).toBe("/project/requirements.txt");
    expect(packageCellTitle(f, "pkg")).toBe("requests@2.19.0");
    expect(packageCellTitle(f, "msg")).toBe("GHSA-0001 Header injection");
    expect(packageCellTitle(f, "sev")).toBeUndefined();
    expect(packageCellTitle(f, "line")).toBeUndefined();
  });

  it("has no package tooltip for a finding without a package", () => {
    expect(packageCellTitle(finding({ package: "" }), "pkg")).toBeUndefined();
  });
});

describe("severity and tone colours", () => {
  it("colours each severity as the AppKit window does", () => {
    expect(severityStyle("critical")).toContain("var(--system-red)");
    expect(severityStyle("high")).toContain("var(--system-orange)");
    expect(severityStyle("medium")).toContain("var(--system-yellow)");
    expect(severityStyle("low")).toContain("var(--system-gray)");
  });

  it("colours the status line by its tone", () => {
    expect(toneColor("warning")).toBe("var(--system-orange)");
    expect(toneColor("error")).toBe("var(--system-red)");
    expect(toneColor("secondary")).toBe("var(--secondary-label)");
  });
});

describe("vulnerabilityQuestion", () => {
  it("asks the AI about the finding's message", () => {
    expect(vulnerabilityQuestion(finding())).toBe(
      "Is the currently open project vulnerable to: GHSA-0001 Header injection",
    );
  });
});
