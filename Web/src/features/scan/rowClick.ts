// Mouse clicks on the shared `Table` select a row and then bubble up to the table's wrapper. AppKit's
// `rowClicked` opens the selected row on every click, while keyboard moves only select. These helpers
// let a wrapper tell the two apart: a click counts only when it lands on a row.

/** The selected row when the click landed on a row of the table, otherwise undefined. */
export function clickedRow<R>(
  event: MouseEvent,
  rows: readonly R[],
  rowId: (row: R) => string,
  selectedKey: string | null,
): R | undefined {
  if (!(event.target instanceof Element) || !event.target.closest('[role="row"]')) return undefined;
  return rows.find((row) => rowId(row) === selectedKey);
}
