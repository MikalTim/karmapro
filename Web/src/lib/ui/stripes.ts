// NSTableView and NSOutlineView with `usesAlternatingRowBackgroundColors` keep alternating the row colour
// through the empty space below the last row. This builds that background for the filler under the rows.

/**
 * A repeating vertical gradient of two bands of `rowHeight` pixels. The first band has the alternate colour
 * when `firstIsAlternate` is true, which is the case when the last real row is a plain one.
 */
export function stripeBackground(rowHeight: number, firstIsAlternate: boolean): string {
  const [first, second] = firstIsAlternate ? ["var(--row-alt)", "transparent"] : ["transparent", "var(--row-alt)"];
  return `repeating-linear-gradient(to bottom, ${first} 0, ${first} ${rowHeight}px, ${second} ${rowHeight}px, ${second} ${rowHeight * 2}px)`;
}

/** Rows alternate starting with a plain row 0, so every odd row is the alternate one. */
export function isAlternateRow(index: number): boolean {
  return index % 2 === 1;
}

/** The width the last column takes when it fills the table: what the other columns leave, never below `minWidth`. */
export function lastColumnWidth(viewWidth: number, otherWidths: number, minWidth: number, ownWidth: number): number {
  // Before the table has been measured there is no view width, so the column keeps its own width.
  if (viewWidth <= 0) return ownWidth;
  return Math.max(minWidth, viewWidth - otherWidths);
}
