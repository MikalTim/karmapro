// Text fitting for the diagram ports. AppKit wraps and truncates with the text system
// (`NSString.draw(in:)`, `.byTruncatingTail`, `.byTruncatingMiddle`); SVG has neither, so the
// same decisions are made here from a width function, which the components back with
// `measureText`. The width function is injected so the rules can be tested without a DOM.

export type Measure = (text: string) => number;

const ELLIPSIS = "\u2026";

/** The UI font stack of `--font-ui`, for canvas font strings. */
export const UI_FONT_FAMILY = '-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif';

/** The monospaced stack of `--font-mono`, for canvas font strings. */
export const MONO_FONT_FAMILY = 'ui-monospace, "SF Mono", Menlo, "DejaVu Sans Mono", monospace';

/** A canvas font string for `measureText`: weight, size in px, then the family. */
export function uiFont(size: number, weight: number): string {
  return `${weight} ${size}px ${UI_FONT_FAMILY}`;
}

export function monoFont(size: number, weight: number): string {
  return `${weight} ${size}px ${MONO_FONT_FAMILY}`;
}

/**
 * Word-wraps `text` to `maxWidth`, as `boundingRect(with:options:)` and `draw(in:)` do. A word
 * wider than a whole line is broken between characters. Newlines start a new paragraph.
 */
export function wrapLines(text: string, maxWidth: number, measure: Measure): string[] {
  const lines: string[] = [];
  for (const paragraph of text.split("\n")) {
    if (paragraph === "") continue;
    wrapParagraph(paragraph, maxWidth, measure, lines);
  }
  return lines;
}

function wrapParagraph(paragraph: string, maxWidth: number, measure: Measure, lines: string[]): void {
  let line = "";
  for (const word of paragraph.split(" ")) {
    const candidate = line === "" ? word : `${line} ${word}`;
    if (measure(candidate) <= maxWidth) {
      line = candidate;
      continue;
    }
    if (line !== "") {
      lines.push(line);
      line = "";
      if (measure(word) <= maxWidth) {
        line = word;
        continue;
      }
    }
    for (const character of word) {
      if (line !== "" && measure(line + character) > maxWidth) {
        lines.push(line);
        line = "";
      }
      line += character;
    }
  }
  if (line !== "") lines.push(line);
}

/** `.byTruncatingTail`: the longest prefix that fits with an ellipsis, or the text when it fits. */
export function truncateTail(text: string, maxWidth: number, measure: Measure): string {
  if (measure(text) <= maxWidth) return text;
  const characters = [...text];
  for (let kept = characters.length - 1; kept > 0; kept--) {
    const candidate = characters.slice(0, kept).join("") + ELLIPSIS;
    if (measure(candidate) <= maxWidth) return candidate;
  }
  return ELLIPSIS;
}

/** `.byTruncatingMiddle`: the longest head and tail that fit around an ellipsis. */
export function truncateMiddle(text: string, maxWidth: number, measure: Measure): string {
  if (measure(text) <= maxWidth) return text;
  const characters = [...text];
  for (let kept = characters.length - 1; kept > 0; kept--) {
    const head = Math.ceil(kept / 2);
    const tail = Math.floor(kept / 2);
    const candidate = characters.slice(0, head).join("") + ELLIPSIS + characters.slice(characters.length - tail).join("");
    if (measure(candidate) <= maxWidth) return candidate;
  }
  return ELLIPSIS;
}
