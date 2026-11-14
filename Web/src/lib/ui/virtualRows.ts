// Measured row offsets for Table's wrapping, virtualised layout. Unknown rows use the minimum row height
// until they enter the rendered window and ResizeObserver measures their actual height.

export function rowOffsets<Row>(rows: readonly Row[], height: (row: Row) => number, minimum: number): number[] {
  const offsets = new Array<number>(rows.length + 1);
  offsets[0] = 0;
  for (let index = 0; index < rows.length; index++) {
    offsets[index + 1] = offsets[index] + Math.max(minimum, height(rows[index]));
  }
  return offsets;
}

/** The row containing an offset; exact boundaries belong to the following row. Empty lists return zero. */
export function rowAtOffset(offsets: readonly number[], position: number): number {
  const count = offsets.length - 1;
  let low = 0;
  let high = count;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (offsets[middle + 1] <= position) low = middle + 1;
    else high = middle;
  }
  return Math.min(low, Math.max(0, count - 1));
}

/** A half-open row window, including overscan. A row starting at the bottom edge is not visible yet. */
export function visibleRowWindow(
  offsets: readonly number[],
  scrollTop: number,
  viewHeight: number,
  overscan: number,
): { first: number; last: number } {
  const count = offsets.length - 1;
  if (count === 0) return { first: 0, last: 0 };
  const top = Math.max(0, scrollTop);
  const start = rowAtOffset(offsets, top);
  const bottom = top + Math.max(0, viewHeight);
  let low = start;
  let high = count;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (offsets[middle] < bottom) low = middle + 1;
    else high = middle;
  }
  return { first: Math.max(0, start - overscan), last: Math.min(count, Math.max(start + 1, low) + overscan) };
}
