// Presentation rules of the Security Scan window (`ScanWindowController`): table columns and cell
// text, sort descriptors, the status line, button states, and which alert is due. The server
// (`SecurityScanService`) owns the findings and every decision that changes them. Nothing here
// touches the network or the DOM, so the rules can be tested on their own.

export type Awareness = "introduced" | "contextual" | "preExisting" | "fixed";

/** One row of the results table (`SecurityScanService.FindingDTO`). */
export interface FindingDTO {
  /** `"<path>#<line>"`, the key the ignore list uses. */
  key: string;
  path: string;
  displayPath: string;
  line: number;
  function: string;
  category: string;
  /** The finding text before the window's decoration. */
  message: string;
  taintPath?: string | null;
  severity: string;
  /** 3 (critical) to 0 (low). */
  severityRank: number;
  exploitability: string;
  exploitabilityRank: number;
  reachable: boolean;
  crossFile: boolean;
  /** The Engine column: "AST", "Heuristic", "AI", or several joined by ", ". */
  engine: string;
  awareness?: Awareness | null;
  /** AI triage verdict: true = valid, false = not valid, absent = not checked. */
  triage?: boolean | null;
}

/** An alert the window shows. `id` grows with every alert, so each one is shown once. */
export interface NoticeDTO {
  id: number;
  title: string;
  message: string;
}

/** The window's state (`SecurityScanService.StateDTO`). The server omits nil values. */
export interface StateDTO {
  title: string;
  status: string;
  statusIsAIPhase: boolean;
  progress?: number | null;
  progressIndeterminate: boolean;
  aiThinking: boolean;
  rows: FindingDTO[];
  showPullRequestColumn: boolean;
  showTriageColumn: boolean;
  canRescan: boolean;
  canExport: boolean;
  canTriage: boolean;
  triageRunning: boolean;
  notice?: NoticeDTO | null;
}

/** A question the server words (`SecurityScanService.ScanPromptDTO`). */
export interface ScanPromptDTO {
  message: string;
  informative: string;
  buttons: string[];
}

/** A table sort descriptor: the server's sort key and direction. */
export interface SortChoice {
  key: string;
  ascending: boolean;
}

/** The state before the first fetch. It equals the server's state before any scan. */
export const EMPTY_STATE: StateDTO = {
  title: "Security Scan",
  status: "No scan has been run yet.",
  statusIsAIPhase: false,
  progress: null,
  progressIndeterminate: false,
  aiThinking: false,
  rows: [],
  showPullRequestColumn: false,
  showTriageColumn: false,
  canRescan: true,
  canExport: false,
  canTriage: false,
  triageRunning: false,
  notice: null,
};

// MARK: - Columns

export type ColumnId = "exp" | "sev" | "cat" | "fn" | "file" | "line" | "src" | "crossfile" | "inpr" | "triage" | "msg";

export interface ColumnSpec {
  id: ColumnId;
  title: string;
  width: number;
  align: "left" | "center" | "right";
  /** The column's sort descriptor prototype. Absent when the column is not sortable. */
  sort?: SortChoice;
}

/** Every column in table order. "In PR?" and "Triage" are shown only when the window asks for them. */
export const COLUMNS: readonly ColumnSpec[] = [
  { id: "exp", title: "Exploitability", width: 92, align: "left", sort: { key: "exploitability", ascending: false } },
  { id: "sev", title: "Severity", width: 80, align: "left", sort: { key: "severity", ascending: false } },
  { id: "cat", title: "Category", width: 180, align: "left", sort: { key: "category", ascending: true } },
  { id: "fn", title: "Function", width: 150, align: "left", sort: { key: "function", ascending: true } },
  { id: "file", title: "File", width: 160, align: "left", sort: { key: "fileURL", ascending: true } },
  { id: "line", title: "Line", width: 50, align: "right", sort: { key: "line", ascending: true } },
  { id: "src", title: "Engine", width: 90, align: "center", sort: { key: "scanningSource", ascending: true } },
  { id: "crossfile", title: "Cross-file", width: 80, align: "center", sort: { key: "crossFile", ascending: false } },
  { id: "inpr", title: "In PR?", width: 90, align: "center", sort: { key: "inpr", ascending: true } },
  { id: "triage", title: "Triage", width: 70, align: "center" },
  { id: "msg", title: "Finding", width: 300, align: "left" },
];

export function visibleColumns(state: Pick<StateDTO, "showPullRequestColumn" | "showTriageColumn">): ColumnSpec[] {
  return COLUMNS.filter(
    (column) =>
      (column.id !== "inpr" || state.showPullRequestColumn) && (column.id !== "triage" || state.showTriageColumn),
  );
}

/**
 * The sort after a header click. Clicking the sorted column reverses it. Clicking another column
 * sorts by it in that column's prototype direction, as `NSTableView` does.
 */
export function nextSort(current: SortChoice | null, prototype: SortChoice): SortChoice {
  if (current && current.key === prototype.key) return { key: current.key, ascending: !current.ascending };
  return { ...prototype };
}

// MARK: - Cells

export interface CellPart {
  text: string;
  color: string;
  weight: 400 | 600 | 700;
  size: number;
}

export interface CellView {
  parts: CellPart[];
  tooltip: string | null;
}

const LABEL = "var(--label)";
const SECONDARY = "var(--secondary-label)";
const BODY_SIZE = 12;

/** The colour of a severity, and of an exploitability (which uses the same scale). */
export function levelColor(rank: number): string {
  switch (rank) {
    case 3:
      return "var(--system-red)";
    case 2:
      return "var(--system-orange)";
    case 1:
      return "var(--system-yellow)";
    default:
      return "var(--system-gray)";
  }
}

/** The Engine colours: the AI purple, AST green, every other engine blue. */
export function engineColor(engine: string): string {
  if (engine === "AI") return "var(--system-purple)";
  if (engine === "AST") return "var(--system-green)";
  return "var(--system-blue)";
}

function part(text: string, color: string = LABEL, weight: CellPart["weight"] = 400, size: number = BODY_SIZE): CellPart {
  return { text, color, weight, size };
}

function makeCell(parts: CellPart[], tooltip: string | null = null): CellView {
  return { parts, tooltip };
}

function plainCell(text: string, tooltip: string | null = null): CellView {
  return makeCell([part(text)], tooltip);
}

/** The Finding column's text: the taint flow, the message, and the unreachable note. */
export function findingText(row: FindingDTO): string {
  const lines: string[] = [];
  if (row.taintPath) lines.push(`flow: ${row.taintPath}`);
  lines.push(row.engine === "AI" ? `flow: ${row.message}` : row.message);
  if (!row.reachable) lines.push("(function not reachable from entry point)");
  return lines.join("\n");
}

function engineCell(engine: string): CellView {
  const engines = engine.split(",").map((name) => name.trim());
  const parts: CellPart[] = [];
  engines.forEach((name, index) => {
    if (index > 0) parts.push(part(", "));
    parts.push(part(name, engineColor(name), name === "AI" || name === "AST" ? 700 : 600));
  });
  let tooltip: string | null = null;
  if (engines.length > 1) tooltip = `Reported by ${engine}.`;
  else if (engine === "AI") tooltip = "Found by the AI assistant model during the AI deep scan phase.";
  return makeCell(parts, tooltip);
}

function awarenessCell(awareness: Awareness | null): CellView {
  switch (awareness) {
    case "introduced":
      return makeCell([part("New", "var(--system-red)", 700)], "Introduced by this pull request.");
    case "contextual":
      return makeCell(
        [part("Touched", "var(--system-orange)", 600)],
        "In a file this PR modifies, but not on changed lines and not present at base.",
      );
    case "preExisting":
      return makeCell([part("Pre-existing", SECONDARY)], "Already present before this pull request.");
    case "fixed":
      return makeCell(
        [part("Fixed", "var(--system-green)")],
        "Present at the base commit and gone from this pull request. The line number shown is the base revision's.",
      );
    case null:
      return plainCell("");
  }
}

function triageCell(valid: boolean | null): CellView {
  if (valid === null) return plainCell("");
  return valid
    ? makeCell([part("\u2713", "var(--system-red)", 700, 14)], "AI triage: the model judges this a valid issue.")
    : makeCell([part("\u2717", SECONDARY, 700, 14)], "AI triage: the model judges this not a valid issue.");
}

/** The text and styling of one table cell, as `ScanWindowController.tableView(_:viewFor:row:)` builds it. */
export function cellFor(row: FindingDTO, column: ColumnId): CellView {
  switch (column) {
    case "exp":
      return makeCell([part(row.exploitability, levelColor(row.exploitabilityRank), 700)]);
    case "sev":
      return makeCell([part(row.severity, levelColor(row.severityRank), 600)]);
    case "cat":
      return plainCell(row.category);
    case "fn":
      return row.reachable
        ? plainCell(row.function, "Function is reachable from an entry point.")
        : plainCell(`${row.function}  \u21E2`, "Function is NOT reachable from an entry point in this file.");
    case "file":
      return plainCell(row.displayPath, row.path);
    case "line":
      // A fixed finding comes from the base scan, so its line is a base-revision coordinate.
      return row.awareness === "fixed"
        ? makeCell([part(`${row.line} (base)`, SECONDARY)], `Line ${row.line} of the base revision, not of the current file.`)
        : plainCell(String(row.line));
    case "src":
      return engineCell(row.engine);
    case "crossfile":
      return row.crossFile
        ? makeCell([part("Yes", "var(--system-orange)", 600)], "Taint originates from a source defined in another file.")
        : plainCell("No", "Taint is local to this file or from a built-in source.");
    case "inpr":
      return awarenessCell(row.awareness ?? null);
    case "triage":
      return triageCell(row.triage ?? null);
    case "msg":
      return plainCell(findingText(row), findingText(row));
  }
}

// MARK: - Status line and buttons

const AI_PHASE_PREFIX = "AI phase: ";

/**
 * The status line. While the AI pass runs, "AI phase: " is bold purple and the rest green, as
 * `setStatusAIPhase` draws it.
 */
export function statusParts(state: Pick<StateDTO, "status" | "statusIsAIPhase">): CellPart[] {
  if (state.statusIsAIPhase && state.status.startsWith(AI_PHASE_PREFIX)) {
    return [
      part(AI_PHASE_PREFIX, "var(--system-purple)", 700),
      part(state.status.slice(AI_PHASE_PREFIX.length), "var(--system-green)"),
    ];
  }
  return [part(state.status, SECONDARY)];
}

/** The Triage (AI) button: purple when it can run, gray and faded otherwise (`refreshAutoTriageButton`). */
export function triageLook(enabled: boolean): { background: string; opacity: number } {
  return enabled ? { background: "var(--system-purple)", opacity: 1 } : { background: "var(--system-gray)", opacity: 0.6 };
}

/** The finding at `index`, or null when nothing is selected or the row has gone. */
export function rowAt(rows: readonly FindingDTO[], index: number | null): FindingDTO | null {
  if (index === null || index < 0 || index >= rows.length) return null;
  return rows[index];
}

// MARK: - Window lifecycle and alerts

/**
 * What closing the window stops (`windowWillClose`). A plain scan or a triage stops. A pull request
 * review keeps its scan running (the app does not stop it either), so only its triage stops.
 */
export function closeCancel(
  state: Pick<StateDTO, "showPullRequestColumn" | "canRescan" | "triageRunning">,
): "cancelScan" | "cancelTriage" | null {
  if (!state.showPullRequestColumn) return state.canRescan ? null : "cancelScan";
  return state.triageRunning ? "cancelTriage" : null;
}

/**
 * The notice to show now, if it is new. `seen` is null until the first state arrives, so an alert
 * raised before this page started is not shown.
 */
export function pendingNotice(notice: NoticeDTO | null | undefined, seen: number | null): NoticeDTO | null {
  if (!notice || seen === null) return null;
  return notice.id > seen ? notice : null;
}

export function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
