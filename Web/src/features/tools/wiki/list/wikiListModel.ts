// The wiki list's rules (WikiWindowController): the DTO shapes, the table
// cells, the rename and delete texts, the password and backup texts, and the
// answers to import conflicts. The window and `wikiActions.ts` call these;
// nothing here touches the page or the server.
import { ApiError } from "../../../../lib/api";
import type { AlertResult } from "../../../../lib/ui/alert.svelte";

/** One page as the list shows it (`WikiService.WikiPageDTO`). */
export interface WikiPageDTO {
  slug: string;
  title: string;
  created: number;
  updated: number;
  createdText: string;
  updatedText: string;
}

/** `GET /api/wiki` (`WikiService.WikiListDTO`). */
export interface WikiListDTO {
  pages: WikiPageDTO[];
  statusText: string;
}

/** `POST /api/wiki/import` (`WikiService.WikiImportSessionDTO`). */
export interface WikiImportSessionDTO {
  importID: string;
  conflicts: string[];
  conflictTitles: Record<string, string>;
}

/** `POST /api/wiki/import/:importID/resolve` (`WikiService.WikiImportResultDTO`). */
export interface WikiImportResultDTO {
  imported: number;
  overwritten: number;
  renamed: number;
  skipped: number;
  summary: string;
}

/** What to do with a page that already exists: the `WikiStore.Conflict` raw values. */
export type WikiConflictChoice = "overwrite" | "rename" | "skip";

/** The conflict alert's buttons, in the order `askConflict` adds them. */
export const CONFLICT_BUTTONS: string[] = ["Overwrite", "Rename Imported", "Skip", "Cancel Import"];

/** Index of "Cancel Import": it skips every conflict that has not been asked about yet. */
const CANCEL_IMPORT = 3;

/** The text of one table cell (`tableView(_:viewFor:row:)`). Unknown columns show nothing. */
export function wikiCellValue(page: WikiPageDTO, columnId: string): string {
  switch (columnId) {
    case "title":
      return page.title;
    case "created":
      return page.createdText;
    case "updated":
      return page.updatedText;
    default:
      return "";
  }
}

/** The title a rename sends, or null when the window changes nothing (cancelled, blank or unchanged). */
export function renamedTitle(current: string, entered: string | null): string | null {
  if (entered === null || entered.trim() === "" || entered === current) return null;
  return entered;
}

/** The selected page after the list reloads: it stays selected only while it is still listed. */
export function selectionAfterReload(pages: WikiPageDTO[], selectedSlug: string | null): string | null {
  return selectedSlug !== null && pages.some((page) => page.slug === selectedSlug) ? selectedSlug : null;
}

/** The "Delete Page" confirmation text (`deleteClicked`). */
export function deleteConfirmText(title: string): string {
  return `Delete "${title}" permanently? This cannot be undone.`;
}

/** The "Backup Saved" text (`backupClicked`). */
export function backupSavedText(total: number, fileName: string, protectedBackup: boolean): string {
  return `Exported ${total} page${total === 1 ? "" : "s"} to ${fileName}.` + (protectedBackup ? "\nThis backup is password protected." : "");
}

/** The "Page Already Exists" text for one conflicting page (`askConflict`). */
export function conflictInformativeText(title: string): string {
  return `"${title}" already exists in your wiki. What should happen to the imported copy?`;
}

function conflictChoice(button: number): WikiConflictChoice {
  switch (button) {
    case 0:
      return "overwrite";
    case 1:
      return "rename";
    default:
      return "skip";
  }
}

/**
 * Asks once per conflicting slug, in the order the server lists them. "Cancel Import"
 * skips that slug and every slug after it without asking again (plan: "skip all").
 */
export async function collectConflictDecisions(
  conflicts: string[],
  ask: (slug: string) => Promise<number>,
): Promise<Record<string, WikiConflictChoice>> {
  const decisions: Record<string, WikiConflictChoice> = {};
  let skipAll = false;
  for (const slug of conflicts) {
    if (skipAll) {
      decisions[slug] = "skip";
      continue;
    }
    const button = await ask(slug);
    if (button === CANCEL_IMPORT) {
      skipAll = true;
      decisions[slug] = "skip";
      continue;
    }
    decisions[slug] = conflictChoice(button);
  }
  return decisions;
}

/** True for the 422 answer that asks for a backup password (`needsPassword: true`). */
export function needsPasswordAnswer(error: unknown): boolean {
  if (!(error instanceof ApiError) || error.status !== 422) return false;
  const body: unknown = error.body;
  return typeof body === "object" && body !== null && "needsPassword" in body && body.needsPassword === true;
}

/** The typed password, or null when the prompt was cancelled or left blank. */
export function passwordOrNull(result: AlertResult): string | null {
  if (result.button !== 0) return null;
  const value = result.values[0] ?? "";
  return value === "" ? null : value;
}

/** The backup's two password prompts agree, and neither was cancelled or blank. */
export function passwordsMatch(first: string | null, confirmed: string | null): first is string {
  return first !== null && confirmed !== null && first === confirmed;
}

/** The text to show for a failed request: the server's own message, or the error's text. */
export function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
