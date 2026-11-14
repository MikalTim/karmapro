// Pure logic of the Search in Files window: what it asks the server, its title,
// and how each match is labelled in its one-column table.
import type { Column } from "../../../lib/ui/Table.svelte";

/** One matching line (`SearchService.MatchDTO`). */
export interface SearchMatch {
  path: string;
  relativePath: string;
  line: number;
  text: string;
}

/** The job result (`SearchService.ResultDTO`). */
export interface SearchResult {
  term: string;
  statusText: string;
  matches: SearchMatch[];
}

export interface SearchRow {
  id: string;
  match: SearchMatch;
  /** "file:line", the bold part of the row. */
  head: string;
  body: string;
}

export const SEARCH_PLACEHOLDER = "Search across all files…";
export const SEARCH_PROMPT_STATUS = "Type a query to search all files in the folder.";
export const SEARCH_RUNNING_STATUS = "Searching…";

const ALL_LANGUAGES = "All Languages";
const MATCH_MIN_WIDTH = 600;

/** The language to search, or undefined for every file (the popup's "All Languages"). */
export function searchLanguage(language: string | null): string | undefined {
  return language === null || language === "" || language === ALL_LANGUAGES ? undefined : language;
}

export function searchRequest(term: string, language: string | null): { term: string; language: string | undefined } {
  return { term, language: searchLanguage(language) };
}

export function searchWindowTitle(language: string | null): string {
  const name = searchLanguage(language);
  return name === undefined ? "Search in Files" : `Search in Files (${name})`;
}

export function fileNameOf(path: string): string {
  return path.slice(path.lastIndexOf("/") + 1);
}

export function matchRows(matches: SearchMatch[]): SearchRow[] {
  return matches.map((match) => ({
    id: `${match.path}:${match.line}`,
    match,
    head: `${fileNameOf(match.path)}:${match.line}`,
    body: match.text,
  }));
}

/** The one column fills the table; it is never narrower than AppKit's 600 pt. */
export function searchColumns(tableWidth: number): Column<SearchRow>[] {
  return [{ id: "snippet", title: "Match", width: Math.max(MATCH_MIN_WIDTH, tableWidth) }];
}
