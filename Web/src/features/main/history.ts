// Back and forward through the files shown in the source viewer. The rules are
// those of `MainWindowController.recordHistory`, `navigateHistory` and
// `historyMenuChosen`: showing the file already current records nothing, a new
// file drops the forward entries, and Back or Forward only move the index.
import { baseName } from "./paths";

export interface FileHistory {
  readonly entries: readonly string[];
  /** Position of the file on screen, or -1 before any file was shown. */
  readonly index: number;
}

/** How many files the press-and-hold menu lists. */
export const HISTORY_MENU_LENGTH = 10;

export const EMPTY_HISTORY: FileHistory = { entries: [], index: -1 };

export interface HistoryMenuEntry {
  /** Index of the entry in the whole history, used to jump to it. */
  index: number;
  name: string;
  path: string;
}

/** Records a file as shown. Showing the current file again changes nothing. */
export function recordFile(history: FileHistory, path: string): FileHistory {
  if (history.entries[history.index] === path) return history;
  const entries = [...history.entries.slice(0, history.index + 1), path];
  return { entries, index: entries.length - 1 };
}

export function canGoBack(history: FileHistory): boolean {
  return history.index > 0;
}

export function canGoForward(history: FileHistory): boolean {
  return history.index >= 0 && history.index < history.entries.length - 1;
}

/** Steps one entry back or forward, keeping the forward entries. Null at either end. */
export function stepHistory(history: FileHistory, delta: -1 | 1): FileHistory | null {
  const target = history.index + delta;
  if (target < 0 || target >= history.entries.length) return null;
  return { entries: history.entries, index: target };
}

/** Jumps to an entry picked from the menu and drops the entries after it, as a browser does. */
export function jumpToHistory(history: FileHistory, index: number): FileHistory | null {
  if (index < 0 || index >= history.entries.length) return null;
  return { entries: history.entries.slice(0, index + 1), index };
}

/** The newest entries first, taken from the whole history including the forward entries. */
export function historyMenuEntries(history: FileHistory): HistoryMenuEntry[] {
  const count = Math.min(history.entries.length, HISTORY_MENU_LENGTH);
  const entries: HistoryMenuEntry[] = [];
  for (let index = history.entries.length - 1; index >= history.entries.length - count; index--) {
    const path = history.entries[index];
    entries.push({ index, name: baseName(path), path });
  }
  return entries;
}
