// The bug tracker's rules as plain functions: what a list cell shows, what the
// detail panel says, what the editor accepts, and which answers ask for a
// password. The server keeps the reports; the windows only draw these rules.
import { ApiError } from "../../../lib/api";
import type { AlertResult } from "../../../lib/ui/alert.svelte";

/** One report as the server sends it (`BugService.BugDTO`). */
export interface BugDTO {
  id: string;
  title: string;
  severity: string;
  exploitability: string;
  detail: string;
  packageName: string;
  version: string;
  status: string;
  createdAt: string;
  createdText: string;
  shortID: string;
  packageText: string;
  filePath?: string | null;
  line?: number | null;
}

/** The editor's fields (`BugService.BugInputDTO`). */
export interface BugInput {
  title: string;
  severity: string;
  exploitability: string;
  detail: string;
  packageName: string;
  version: string;
  status: string;
}

export interface BugColumn {
  id: string;
  title: string;
  width: number;
}

/** `GET /api/bugs` (`BugService.BugListDTO`). */
export interface BugListDTO {
  bugs: BugDTO[];
  openCount: number;
  countText: string;
  columns: BugColumn[];
}

export interface BugPreset {
  title: string;
  description: string | null;
}

/** `GET /api/bugs/choices` (`BugService.BugChoicesDTO`). */
export interface BugChoicesDTO {
  severities: string[];
  statuses: string[];
  presets: BugPreset[];
  defaults: BugInput;
}

/** `POST /api/bugs/import` (`BugService.BugImportResultDTO`). */
export interface BugImportResultDTO {
  added: number;
  found: number;
  encrypted: boolean;
}

/** The severity colours of `BugListWindowController.severityColor`, as the theme's variables. */
export function severityColor(level: string): string {
  switch (level) {
    case "critical":
      return "var(--system-red)";
    case "high":
      return "var(--system-orange)";
    case "medium":
      return "var(--system-yellow)";
    case "low":
      return "var(--system-green)";
    default:
      return "var(--secondary-label)";
  }
}

/** The text of one table cell (`tableView(_:viewFor:row:)`). Unknown columns show nothing. */
export function bugCellValue(bug: BugDTO, columnId: string): string {
  switch (columnId) {
    case "id":
      return bug.shortID;
    case "title":
      return bug.title;
    case "severity":
      return bug.severity;
    case "exploitability":
      return bug.exploitability;
    case "package":
      return bug.packageText;
    case "status":
      return bug.status;
    case "created":
      return bug.createdText;
    default:
      return "";
  }
}

/** The detail panel's metadata lines (`showDetail(for:)`). */
export function bugDetailMeta(bug: BugDTO): string {
  let meta = `Severity: ${bug.severity}   ·   Exploitability: ${bug.exploitability}   ·   Status: ${bug.status}`;
  meta += `\nCreated: ${bug.createdText}`;
  if (bug.packageName) {
    meta += `\nPackage: ${bug.packageName}`;
    if (bug.version) meta += `   v${bug.version}`;
  }
  return meta;
}

/** The detail panel's description; a report without one says so. */
export function bugDetailBody(bug: BugDTO): string {
  return bug.detail === "" ? "(no description)" : bug.detail;
}

/** A new report starts with the server's defaults, as the editor's popups do. */
export function newBugForm(defaults: BugInput): BugInput {
  return { ...defaults };
}

/** A saved report as the form fields that populate the editor. */
export function formFromBug(bug: BugDTO): BugInput {
  return {
    title: bug.title,
    severity: bug.severity,
    exploitability: bug.exploitability,
    detail: bug.detail,
    packageName: bug.packageName,
    version: bug.version,
    status: bug.status,
  };
}

/**
 * The editor's Save rule (`saveClicked`): the title is required after trimming;
 * package and version are trimmed; the description is kept as typed.
 * Returns the request body, or the message the editor shows in red.
 */
export function buildBugInput(form: BugInput): { input: BugInput } | { error: string } {
  const title = form.title.trim();
  if (title === "") return { error: "A title is required." };
  return {
    input: {
      title,
      severity: form.severity,
      exploitability: form.exploitability,
      detail: form.detail,
      packageName: form.packageName.trim(),
      version: form.version.trim(),
      status: form.status,
    },
  };
}

/**
 * What choosing a title-menu item fills in (`titleMenuItemSelected`). Index 0 is
 * "Custom title…" and fills nothing; presets follow in server order. A preset
 * without a description leaves the current description alone (null).
 */
export function presetFill(presets: BugPreset[], menuIndex: number): { title: string; description: string | null } | null {
  if (menuIndex <= 0) return null;
  const preset = presets[menuIndex - 1];
  return preset ? { title: preset.title, description: preset.description } : null;
}

/** True for the 422 answer that asks for a backup password (`needsPassword: true`). */
export function isNeedsPasswordError(error: unknown): boolean {
  if (!(error instanceof ApiError) || error.status !== 422) return false;
  const body: unknown = error.body;
  return typeof body === "object" && body !== null && "needsPassword" in body && body.needsPassword === true;
}

/**
 * The text a secure alert returned, or null when it was cancelled or left blank
 * (`promptForExistingPassword` / `promptForNewPassword`). The password is not trimmed.
 */
export function passwordOrNull(result: AlertResult): string | null {
  if (result.button !== 0) return null;
  const value = result.values[0] ?? "";
  return value === "" ? null : value;
}

/** The backup's two password prompts agree, and neither was cancelled or blank. */
export function passwordsMatch(first: string | null, confirmed: string | null): first is string {
  return first !== null && confirmed !== null && first === confirmed;
}

/** The "Backup Saved" text (`backupClicked`). */
export function backupSavedText(total: number, fileName: string, protectedBackup: boolean): string {
  return `Exported ${total} bug reports to ${fileName}.` + (protectedBackup ? "\nThis backup is password protected." : "");
}

/** The "Import Complete" text (`importClicked`). */
export function importCompleteText(added: number, fileName: string): string {
  return `Imported ${added} new bug report(s) from ${fileName}.`;
}

/** The "Delete Bug Report?" text (`deleteClicked`). */
export function deleteConfirmText(title: string): string {
  return `This will permanently remove "${title}".`;
}

/**
 * The selection after the list reloads, as AppKit's table keeps it: the selected row index stays, so the
 * report now at that row is selected (after a delete, the next report). Nothing is selected when the row
 * no longer exists. `previous` is the list shown before the reload.
 */
export function selectionAfterReload(previous: BugDTO[], next: BugDTO[], selectedId: string | null): string | null {
  if (selectedId === null) return null;
  const index = previous.findIndex((bug) => bug.id === selectedId);
  if (index < 0 || index >= next.length) return null;
  return next[index].id;
}

/** The text to show for a failed request: the server's own message, or the error's text. */
export function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
