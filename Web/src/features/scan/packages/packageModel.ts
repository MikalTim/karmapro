// Pure logic of the Scan Project's Packages window. The server owns the scan
// state (`PackageScanService.StateDTO`); these functions turn that state into
// table rows, columns and status text, and build the view shown while a
// request is still running.
import type { Column } from "../../../lib/ui/Table.svelte";

/** One entry of the API source popup. */
export interface PackageApiSource {
  id: string;
  title: string;
  host: string;
}

/** A detected dependency manifest or lockfile. */
export interface PackageFile {
  path: string;
  relativePath: string;
  language: string;
  ecosystem: string;
  isLockfile: boolean;
  kind: string;
  label: string;
}

/** One row of the findings table. */
export interface PackageFinding {
  /** The persisted ignore key of the row. */
  key: string;
  path: string;
  file: string;
  package: string;
  severity: string;
  severityLabel: string;
  line: number;
  message: string;
}

/** Everything the window shows (`PackageScanService.StateDTO`). */
export interface PackageScanState {
  descriptionText: string;
  apiSources: PackageApiSource[];
  selectedApiSource: string;
  privacyNote: string;
  files: PackageFile[];
  findings: PackageFinding[];
  statusText: string;
  /** "secondary", "warning" or "error". */
  statusTone: string;
  busy: boolean;
  /** 0 to 1, or null when the bar is indeterminate. */
  progress: number | null;
  scanEnabled: boolean;
  exportEnabled: boolean;
  sortKey: string | null;
  sortAscending: boolean;
}

export interface PackageRow {
  /** Unique within the table, even when two findings share an ignore key. */
  id: string;
  finding: PackageFinding;
}

export const ASK_AI_TITLE = "(AI) Is it vulnerable?";
export const DETECTING_STATUS = "Detecting package files…";
export const NO_FILES_TEXT = "(no supported dependency manifests or lockfiles found)";

const SEVERITY_WIDTH = 84;
const PACKAGE_WIDTH = 200;
const FILE_WIDTH = 160;
const LINE_WIDTH = 50;
const MESSAGE_MIN_WIDTH = 320;
/** The table's own border, which the Finding column cannot fill. */
const TABLE_BORDER = 2;

const SEVERITY_COLOURS: Record<string, string | undefined> = {
  critical: "var(--system-red)",
  high: "var(--system-orange)",
  medium: "var(--system-yellow)",
  low: "var(--system-gray)",
};

const TONE_COLOURS: Record<string, string | undefined> = {
  warning: "var(--system-orange)",
  error: "var(--system-red)",
};

/** Columns whose first click sorts descending (their NSSortDescriptor prototype has `ascending: false`). */
const DESCENDING_FIRST: Record<string, true | undefined> = { severity: true };

/** Gives each finding a row id, numbering repeats so the table's keys stay unique. */
export function packageRows(findings: PackageFinding[]): PackageRow[] {
  const seen = new Map<string, number>();
  return findings.map((finding) => {
    const count = seen.get(finding.key) ?? 0;
    seen.set(finding.key, count + 1);
    return { id: count === 0 ? finding.key : `${finding.key}#${count}`, finding };
  });
}

export function severityStyle(severity: string): string {
  return `color:${SEVERITY_COLOURS[severity] ?? "var(--label)"};font-weight:600`;
}

export function toneColor(tone: string): string {
  return TONE_COLOURS[tone] ?? "var(--secondary-label)";
}

/** The Finding column takes the width the other columns leave, never less than its own minimum. */
export function packageColumns(tableWidth: number): Column<PackageRow>[] {
  const fixed = SEVERITY_WIDTH + PACKAGE_WIDTH + FILE_WIDTH + LINE_WIDTH + TABLE_BORDER;
  return [
    {
      id: "sev",
      title: "Severity",
      width: SEVERITY_WIDTH,
      sortKey: "severity",
      value: (row) => row.finding.severityLabel,
      style: (row) => severityStyle(row.finding.severity),
    },
    { id: "pkg", title: "Package", width: PACKAGE_WIDTH, sortKey: "package", value: (row) => row.finding.package },
    { id: "file", title: "File", width: FILE_WIDTH, sortKey: "fileURL", value: (row) => row.finding.file },
    {
      id: "line",
      title: "Line",
      width: LINE_WIDTH,
      sortKey: "line",
      align: "right",
      value: (row) => String(row.finding.line),
    },
    {
      id: "msg",
      title: "Finding",
      width: Math.max(MESSAGE_MIN_WIDTH, tableWidth - fixed),
      value: (row) => row.finding.message,
    },
  ];
}

/** The tooltip of a cell (`toolTip`); severity and line have none. */
export function packageCellTitle(finding: PackageFinding, columnId: string): string | undefined {
  switch (columnId) {
    case "pkg":
      return finding.package || undefined;
    case "file":
      return finding.path;
    case "msg":
      return finding.message;
    default:
      return undefined;
  }
}

/**
 * The sort a header click asks the server for. The table only knows "the same
 * column toggles, a new column ascends"; AppKit's severity column starts descending.
 */
export function nextPackageSort(
  current: { sortKey: string | null },
  clicked: string,
  tableAscending: boolean,
): { key: string; ascending: boolean } {
  const ascending = clicked === current.sortKey ? tableAscending : DESCENDING_FIRST[clicked] !== true;
  return { key: clicked, ascending };
}

/**
 * NSTableView keeps the selected row index across a reload, so after the rows
 * change the row now at that index is the selected one.
 */
export function keepSelectionIndex(previous: PackageRow[], selectedId: string | null, next: PackageRow[]): string | null {
  const index = previous.findIndex((row) => row.id === selectedId);
  return index >= 0 && index < next.length ? next[index].id : null;
}

/** The view the window shows the moment a detection or scan is requested, before the server answers. */
export function beginRunView(state: PackageScanState): PackageScanState {
  return {
    ...state,
    busy: true,
    scanEnabled: false,
    progress: null,
    statusText: DETECTING_STATUS,
    statusTone: "secondary",
  };
}

/** The view after a request failed. The Scan button comes back only when files were detected. */
export function failedRunView(state: PackageScanState, message: string): PackageScanState {
  return {
    ...state,
    busy: false,
    progress: null,
    scanEnabled: state.files.length > 0,
    statusText: `Scan failed: ${message}`,
    statusTone: "error",
  };
}

/**
 * The file list box: one label per detected file, or the placeholder when a
 * finished detection found nothing (the server reports that as a warning).
 */
export function packageFilesText(state: PackageScanState): string {
  if (state.files.length > 0) return state.files.map((file) => file.label).join("\n");
  return !state.busy && state.statusTone === "warning" ? NO_FILES_TEXT : "";
}

/** The question the "(AI) Is it vulnerable?" menu item sends to the AI window. */
export function vulnerabilityQuestion(finding: PackageFinding): string {
  return `Is the currently open project vulnerable to: ${finding.message}`;
}
