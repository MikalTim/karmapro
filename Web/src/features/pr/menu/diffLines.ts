// The changes window's picker and line highlighting, as pure functions of the server's changes.
import type { PRChanges, PRDiffLine } from "./prTypes";

/** The value of the picker entry shown when there are no reviewable files. */
export const NO_CHANGES_VALUE = "none";

export interface PickerItem {
  title: string;
  value: string;
}

/**
 * The picker's entries: one per changed file, valued by its index. With no files it has the single
 * "No reviewable changes" entry, as `PRDiffWindowController.load` builds it.
 */
export function changesPickerItems(changes: PRChanges): PickerItem[] {
  if (changes.files.length === 0) return [{ title: changes.emptyTitle, value: NO_CHANGES_VALUE }];
  return changes.files.map((file, index) => ({ title: file.title, value: String(index) }));
}

/**
 * Whether a line gets the yellow, bold highlight. Only added lines are highlighted: the heuristic is about what
 * new code does, and a removed line never changes behaviour that a reader has to check.
 */
export function isHighlighted(line: PRDiffLine): boolean {
  return line.suspicious && line.kind === "added";
}
