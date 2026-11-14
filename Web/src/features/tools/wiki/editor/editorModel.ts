// Pure logic for the page editor: edit ranges, link fields, status text and
// shortcuts. Nothing here touches the DOM, so it is tested with vitest directly.
import type { TextStyle, WikiDocument } from "../richText";

/** A selection or caret, in flattened text offsets (UTF-16 units, as the DOM counts them). */
export interface Span {
  start: number;
  end: number;
}

/** The part of a page's header (`WikiPageDTO`) the editor reads. */
export interface WikiPageSummary {
  slug: string;
  title: string;
}

/** `GET /api/wiki/:slug`. */
export interface WikiPageDetail {
  info: WikiPageSummary;
  document: WikiDocument;
}

/** `GET /api/wiki/resolve?target=`; `slug` is null when no page has that name. */
export interface WikiResolution {
  slug: string | null;
}

/** The key of a page's editor window. AppKit keeps one editor per page (`editors[slug]`). */
export function editorWindowKey(slug: string): string {
  return `WikiEditorWindow:${slug}`;
}

/** The classes that draw a run's style; the rules live in RichTextEditor.svelte. */
export function styleClasses(style: TextStyle): string[] {
  const classes: string[] = [];
  if (style.bold) classes.push("wiki-bold");
  if (style.italic) classes.push("wiki-italic");
  if (style.underline) classes.push("wiki-underline");
  if (style.code) classes.push("wiki-code");
  if (style.heading) classes.push("wiki-heading");
  if (style.dim) classes.push("wiki-dim");
  if (style.link !== null) classes.push("wiki-link");
  return classes;
}

/** One replacement that turns the old text into the new one: old [start, oldEnd) becomes `inserted`. */
export interface TextEdit {
  start: number;
  oldEnd: number;
  inserted: string;
}

const isHighSurrogate = (code: number): boolean => code >= 0xd800 && code <= 0xdbff;
const isLowSurrogate = (code: number): boolean => code >= 0xdc00 && code <= 0xdfff;

/**
 * The single replacement that turns `oldText` into `newText`, found from the common
 * prefix and suffix. It serves edits the browser made without `beforeinput`. Surrogate
 * pairs stay whole, so a piece never ends in half an emoji.
 */
export function diffText(oldText: string, newText: string): TextEdit | null {
  if (oldText === newText) return null;
  const limit = Math.min(oldText.length, newText.length);
  let start = 0;
  while (start < limit && oldText[start] === newText[start]) start++;
  if (start > 0 && isHighSurrogate(oldText.charCodeAt(start - 1))) start--;
  let suffix = 0;
  while (
    suffix < limit - start &&
    oldText[oldText.length - 1 - suffix] === newText[newText.length - 1 - suffix]
  ) {
    suffix++;
  }
  if (suffix > 0 && isLowSurrogate(oldText.charCodeAt(oldText.length - suffix))) suffix--;
  return {
    start,
    oldEnd: oldText.length - suffix,
    inserted: newText.slice(start, newText.length - suffix),
  };
}

export type DeleteDirection = "backward" | "forward";
export type DeleteUnit = "character" | "word";

const graphemes = new Intl.Segmenter(undefined, { granularity: "grapheme" });
const words = new Intl.Segmenter(undefined, { granularity: "word" });

/**
 * The text a Backspace or Delete (or its word variant) removes. A selection is removed
 * whole. A collapsed caret removes one user-perceived character, or one word together
 * with the spaces before or after it, as the browser does.
 */
export function deletionRange(text: string, span: Span, direction: DeleteDirection, unit: DeleteUnit): Span {
  if (span.end > span.start) return span;
  const caret = span.start;
  if (unit === "word") return wordRange(text, caret, direction);
  let previous = 0;
  let next = caret;
  for (const segment of graphemes.segment(text)) {
    const start = segment.index;
    const end = start + segment.segment.length;
    if (start < caret) previous = start;
    if (end > caret && next === caret) next = end;
  }
  return direction === "backward" ? { start: previous, end: caret } : { start: caret, end: next };
}

function wordRange(text: string, caret: number, direction: DeleteDirection): Span {
  const segments = Array.from(words.segment(text));
  if (direction === "backward") {
    // Spaces and punctuation go first, then the word before them.
    let start = caret;
    for (let index = segments.length - 1; index >= 0; index--) {
      const segment = segments[index];
      if (segment.index >= caret) continue;
      start = segment.index;
      if (segment.isWordLike) break;
    }
    return { start, end: caret };
  }
  let end = caret;
  for (const segment of segments) {
    const segmentEnd = segment.index + segment.segment.length;
    if (segmentEnd <= caret) continue;
    end = segmentEnd;
    if (segment.isWordLike) break;
  }
  return { start: caret, end };
}

/** The link the Insert Wiki Link dialog creates. The page falls back to the link text and the text to the page. */
export interface LinkFields {
  text: string;
  pageName: string;
}

/** Null when both fields are blank, so confirming the dialog does nothing (`insertLinkClicked`). */
export function linkFromFields(display: string, target: string): LinkFields | null {
  const shownText = display.trim();
  const pageName = target.trim() || shownText;
  if (pageName === "") return null;
  return { text: shownText || pageName, pageName };
}

/** The text a selection becomes when the Link button hyperlinks it; null when it is blank. */
export function selectionLinkText(selected: string): string | null {
  const trimmed = selected.trim();
  return trimmed === "" ? null : trimmed;
}

/** The status line under the page (`updateStatus`). */
export function statusLine(dirty: boolean, title: string, characters: number): string {
  return `${dirty ? "Edited" : "Saved"} — ${title} · ${characters} characters`;
}

/** The address of a link to open in a browser tab; null for wiki and other links. */
export function externalHref(href: string): string | null {
  try {
    const url = new URL(href);
    return url.protocol === "http:" || url.protocol === "https:" ? url.href : null;
  } catch {
    return null;
  }
}

/** ⌘S on macOS, Ctrl+S elsewhere: the Save button's key equivalent. */
export function isSaveShortcut(key: string, command: boolean, control: boolean, mac: boolean): boolean {
  if (key.toLowerCase() !== "s") return false;
  return mac ? command && !control : control && !command;
}

/** Line endings in pasted text become "\n", the only paragraph break a page keeps. */
export function normalizePastedText(text: string): string {
  return text.replace(/\r\n?/g, "\n");
}

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
