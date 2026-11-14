// Middle truncation of table cell text. The AppKit table cells use `lineBreakMode = .byTruncatingMiddle`: text that
// does not fit keeps its start and its end and shows an ellipsis between them. CSS can only cut the end of a line.

const ELLIPSIS = "\u2026";

/**
 * The longest start-and-end form of `text` that fits `available` px, `text` itself when it already fits.
 * `measure` gives the width of a candidate in px; the start gets the extra character when the kept count is odd.
 */
export function middleTruncate(text: string, available: number, measure: (candidate: string) => number): string {
  if (measure(text) <= available) return text;
  const chars = Array.from(text);
  const shorten = (kept: number): string =>
    chars.slice(0, Math.ceil(kept / 2)).join("") + ELLIPSIS + chars.slice(chars.length - Math.floor(kept / 2)).join("");

  let fits = 0;
  let tooLong = chars.length;
  while (tooLong - fits > 1) {
    const middle = Math.ceil((fits + tooLong) / 2);
    if (measure(shorten(middle)) <= available) fits = middle;
    else tooLong = middle;
  }
  return shorten(fits);
}
