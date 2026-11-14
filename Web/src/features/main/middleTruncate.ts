// Truncation in the middle (`NSLineBreakMode.byTruncatingMiddle`): when a name is too
// wide, its start and its end stay and an ellipsis replaces what lies between them.

const ELLIPSIS = "…";

/**
 * `text` fitted into `maxWidth`. `measure` gives the width of a string in the font the
 * text is shown in. The result keeps as many characters as fit, split evenly between
 * the start and the end (the start gets the extra one when the count is odd).
 */
export function truncateMiddle(text: string, maxWidth: number, measure: (text: string) => number): string {
  if (measure(text) <= maxWidth) return text;
  const characters = Array.from(text);
  const build = (kept: number): string => {
    const head = Math.ceil(kept / 2);
    const tail = kept - head;
    return characters.slice(0, head).join("") + ELLIPSIS + characters.slice(characters.length - tail).join("");
  };
  let low = 0;
  let high = characters.length - 1;
  while (low < high) {
    const middle = Math.ceil((low + high) / 2);
    if (measure(build(middle)) <= maxWidth) low = middle;
    else high = middle - 1;
  }
  return build(low);
}
