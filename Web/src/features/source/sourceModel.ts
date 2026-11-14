// What the viewer shows for the server's answers: the context menu's items and their order, find
// matches, the highlight data CodeView takes, and the texts of the viewer's own windows. Nothing here
// touches the DOM, so it is tested directly.
import { type SyntaxTokenKind, type TextRange, type TokenRange, lineStarts } from "../../lib/code/decorations";
import type { FlowArrow, FlowKind } from "../../lib/code/flowArrows";
import type { ContextMenuDTO, FlowArrowDTO, MLLineDTO, TokenDTO } from "./sourceApi";

const TOKEN_KINDS: readonly SyntaxTokenKind[] = ["comment", "string", "number", "keyword", "type", "plain"];
const FLOW_KINDS: readonly FlowKind[] = ["branchTrue", "branchFalse", "loopBack", "rejoin", "flow", "exit"];
const TYPE_EXTENSIONS: Record<string, true> = {
  c: true,
  h: true,
  cpp: true,
  cc: true,
  cxx: true,
  hpp: true,
  hxx: true,
  hh: true,
  java: true,
  cs: true,
  csx: true,
};

function isTokenKind(kind: string): kind is SyntaxTokenKind {
  return TOKEN_KINDS.some((known) => known === kind);
}

function isFlowKind(kind: string): kind is FlowKind {
  return FLOW_KINDS.some((known) => known === kind);
}

function clamp01(value: number): number {
  return Math.min(Math.max(value, 0), 1);
}

/** The server's token list as CodeView takes it. A kind this build does not know is left unstyled. */
export function tokenRanges(tokens: readonly TokenDTO[]): TokenRange[] {
  const ranges: TokenRange[] = [];
  for (const token of tokens) {
    if (isTokenKind(token.kind)) ranges.push({ location: token.location, length: token.length, kind: token.kind });
  }
  return ranges;
}

export function flowArrowsFrom(arrows: readonly FlowArrowDTO[]): FlowArrow[] {
  const result: FlowArrow[] = [];
  for (const arrow of arrows) {
    if (isFlowKind(arrow.kind)) result.push({ fromLine: arrow.fromLine, toLine: arrow.toLine, kind: arrow.kind });
  }
  return result;
}

/** CodeView's `riskLines`: 1-based line → probability for the ML highlights and gutter bars. */
export function riskLinesFrom(lines: readonly MLLineDTO[]): Record<number, number> {
  const record: Record<number, number> = {};
  for (const entry of lines) record[entry.line] = entry.probability;
  return record;
}

/** The highlighted-lines table's Probability text, rounded like `Int((prob * 100).rounded())`. */
export function probabilityPercent(probability: number): number {
  return Math.round(probability * 100);
}

/**
 * The Probability colour of `HighlightedLinesViewController.riskColor`: green at 60%, red at 100%.
 * `color-mix` in sRGB is the same straight-line blend the Swift code computes per channel.
 */
export function probabilityColor(probability: number): string {
  // Two decimals keep the stop percentages exact in the text: 0.8 gives 50%, not 50.000000000000014%.
  const redShare = Math.round(clamp01((probability - 0.6) / 0.4) * 10000) / 100;
  return `color-mix(in srgb, var(--system-red) ${redShare}%, var(--system-green))`;
}

export function highlightedLinesTitle(count: number): string {
  return count === 0 ? "Bayes highlighted lines" : `Bayes highlighted lines (${count})`;
}

export type ViewerMenuId =
  | "copy"
  | "flowArrows"
  | "focus"
  | "exitFocus"
  | "complexity"
  | "flowDiagram"
  | "simulate"
  | "reachability"
  | "followVariable"
  | "backtrace"
  | "entries"
  | "howToFix";

export type ViewerMenuEntry =
  | { kind: "separator" }
  | { kind: "item"; id: ViewerMenuId; title: string; disabled: boolean; checked: boolean; shortcut?: string };

function menuItem(
  id: ViewerMenuId,
  title: string,
  options: { disabled?: boolean; checked?: boolean; shortcut?: string } = {},
): ViewerMenuEntry {
  return { kind: "item", id, title, disabled: options.disabled ?? false, checked: options.checked ?? false, shortcut: options.shortcut };
}

/**
 * `SourceViewer.textView(_:menu:for:at:)`: the items in the order AppKit adds them. Which items appear
 * and their titles come from the server's `ContextMenuDTO`. `mac` picks the modifier name shown for Copy.
 */
export function viewerMenuEntries(menu: ContextMenuDTO, mac: boolean): ViewerMenuEntry[] {
  const entries: ViewerMenuEntry[] = [];
  const separator = (): void => {
    entries.push({ kind: "separator" });
  };
  const name = menu.functionName;

  entries.push(menuItem("copy", "Copy", { disabled: !menu.copyEnabled, shortcut: mac ? "⌘C" : "Ctrl+C" }));
  separator();
  entries.push(menuItem("flowArrows", menu.flowArrowsTitle, { checked: menu.flowArrowsOn }));
  if (name !== null) {
    separator();
    entries.push(menuItem("focus", `Focus on '${name}'`));
  }
  if (menu.exitFocusAvailable) {
    separator();
    entries.push(menuItem("exitFocus", "Exit Focus Mode", { shortcut: "⎋" }));
  }
  separator();
  entries.push(menuItem("complexity", "Complexity distribution"));
  if (name !== null) {
    separator();
    entries.push(menuItem("flowDiagram", `Show Flow Diagram for ${name}`));
    entries.push(menuItem("simulate", `Simulate '${name}' in the Debugger`));
    entries.push(menuItem("reachability", `Show reachability of '${name}'`));
  }
  if (menu.variableName !== null) {
    separator();
    entries.push(menuItem("followVariable", `Follow the variable '${menu.variableName}'`));
  }
  separator();
  entries.push(menuItem("backtrace", "Backtrace Analyser…"));
  separator();
  entries.push(menuItem("entries", "Find external entries"));
  separator();
  entries.push(menuItem("howToFix", "(AI) How to fix it"));
  return entries;
}

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Every case-insensitive, non-overlapping occurrence of `term`, from the start of `source` (`performFind`). */
export function findMatches(source: string, term: string): TextRange[] {
  if (term.length === 0) return [];
  const pattern = new RegExp(escapeRegExp(term), "giu");
  const matches: TextRange[] = [];
  for (let found = pattern.exec(source); found !== null; found = pattern.exec(source)) {
    matches.push({ location: found.index, length: found[0].length });
  }
  return matches;
}

/** The find bar's count label (`updateMatchCount`). */
export function findCountLabel(term: string, count: number, index: number): string {
  if (term.length === 0) return "";
  if (count === 0) return "No matches";
  return `${index + 1}/${count}`;
}

/** The match Enter moves to, wrapping after the last one (`advanceMatch`). -1 when there are no matches. */
export function nextMatchIndex(current: number, count: number): number {
  return count === 0 ? -1 : (current + 1) % count;
}

/** The question "(AI) How to fix it" sends to the assistant (`AIWindowController.askHowToFix`). */
export function howToFixPrompt(path: string, line: number, lineText: string): string {
  return `How to fix the vulnerability at: ${path}:${line}\n\n${lineText}`;
}

/** The languages whose identifiers get the hover type tooltip (`configureTypeTooltip`). */
export function typeLanguageSupported(ext: string): boolean {
  return TYPE_EXTENSIONS[ext.toLowerCase()] === true;
}

/** A rectangle in viewport coordinates, as the popovers take their anchors. */
export interface ViewportRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export const TYPE_TOOLTIP_HEIGHT = 34;

/** The tooltip's width for a type text measured in its font (`showTypeTooltip`). */
export function typeTooltipWidth(textWidth: number): number {
  return Math.max(60, Math.ceil(textWidth) + 20);
}

/** A focus chip's width: its title plus the button's padding, at least 50 px (`TunnelBar.configure`). */
export function chipWidth(titleWidth: number): number {
  return Math.max(50, Math.ceil(titleWidth) + 28);
}

export function lastPathComponent(path: string): string {
  const parts = path.split("/").filter((part) => part.length > 0);
  return parts.at(-1) ?? path;
}

/** The definition window's title (`DefinitionWindowController`). */
export function definitionTitle(path: string): string {
  return `Definition — ${lastPathComponent(path)}`;
}

/** The definition window's location line: the path, and the line once the definition is read. */
export function definitionLocation(path: string, line: number | null): string {
  return line === null ? path : `${path} — line ${line}`;
}

/** The UTF-16 range of the 1-based `line`, without its newline. Null when the line is out of range. */
export function lineRange(source: string, line: number): TextRange | null {
  const starts = lineStarts(source);
  if (line < 1 || line > starts.length) return null;
  const start = starts[line - 1];
  const end = line < starts.length ? starts[line] - 1 : source.length;
  return { location: start, length: end - start };
}

/** The message of a failed request, or the text of anything else that was thrown. */
export function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
