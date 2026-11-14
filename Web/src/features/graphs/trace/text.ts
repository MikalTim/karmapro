// Text sizing for the trace diagrams. The AppKit views size, wrap and truncate
// their labels with NSString in the system fonts, so the browser versions take
// the same CSS font from the theme and measure it on a canvas. The pure helpers
// take the measuring function as a parameter, so the layout tests need no DOM.
import { measureText } from "../../../lib/diagram/measure";

/** The advance width in px of `text` set in the CSS font `font`. */
export type Measure = (text: string, font: string) => number;

/** CSS font shorthands for the system UI and monospaced faces at a size and weight. */
export interface TraceFonts {
  ui(size: number, weight: number): string;
  mono(size: number, weight: number): string;
}

/** Line height of a system font, as `NSLayoutManager` lays it out (about 1.2 em). */
export function lineHeight(size: number): number {
  return size * 1.2;
}

/** Splits `text` into lines no wider than `maxWidth`, breaking at spaces and inside words that are too long. */
export function wrapText(text: string, font: string, maxWidth: number, measure: Measure): string[] {
  const lines: string[] = [];
  let current = "";
  for (const word of text.split(" ")) {
    if (word === "") continue;
    const candidate = current === "" ? word : `${current} ${word}`;
    if (measure(candidate, font) <= maxWidth) {
      current = candidate;
      continue;
    }
    if (current !== "") lines.push(current);
    const pieces = splitWord(word, font, maxWidth, measure);
    lines.push(...pieces.slice(0, -1));
    current = pieces[pieces.length - 1] ?? "";
  }
  if (current !== "") lines.push(current);
  return lines;
}

function splitWord(word: string, font: string, maxWidth: number, measure: Measure): string[] {
  const pieces: string[] = [];
  let rest = word;
  while (rest.length > 1 && measure(rest, font) > maxWidth) {
    let cut = rest.length - 1;
    while (cut > 1 && measure(rest.slice(0, cut), font) > maxWidth) cut--;
    pieces.push(rest.slice(0, cut));
    rest = rest.slice(cut);
  }
  pieces.push(rest);
  return pieces;
}

/** `NSLineBreakMode.byTruncatingTail` for one line: the longest prefix that fits, then "…". */
export function fitLine(text: string, font: string, maxWidth: number, measure: Measure): string {
  if (measure(text, font) <= maxWidth) return text;
  for (let length = text.length - 1; length > 0; length--) {
    const candidate = `${text.slice(0, length)}…`;
    if (measure(candidate, font) <= maxWidth) return candidate;
  }
  return "…";
}

// The canvas measurement is cheap but the diagrams measure the same strings on
// every pointer move, so results are kept. The cache is cleared when it grows
// large, which only happens after very long sessions.
const MAX_CACHED_WIDTHS = 20000;
const widthCache = new Map<string, number>();

export const browserMeasure: Measure = (text, font) => {
  const key = `${font}\n${text}`;
  const known = widthCache.get(key);
  if (known !== undefined) return known;
  if (widthCache.size >= MAX_CACHED_WIDTHS) widthCache.clear();
  const width = measureText(text, font);
  widthCache.set(key, width);
  return width;
};

let uiFamily: string | undefined;
let monoFamily: string | undefined;

function themeFamily(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

/**
 * The page's fonts. The families are read from the theme variables once, on
 * first use, so the measured faces are the rendered faces.
 */
export const browserFonts: TraceFonts = {
  ui(size, weight) {
    uiFamily ??= themeFamily("--font-ui");
    return `${weight} ${size}px ${uiFamily}`;
  },
  mono(size, weight) {
    monoFamily ??= themeFamily("--font-mono");
    return `${weight} ${size}px ${monoFamily}`;
  },
};

/** The longest prefix of `text` that fits with "…" after it: a line cut short by the next line. */
export function ellipsize(text: string, font: string, maxWidth: number, measure: Measure): string {
  for (let length = text.length; length > 0; length--) {
    const candidate = `${text.slice(0, length)}…`;
    if (measure(candidate, font) <= maxWidth) return candidate;
  }
  return "…";
}
