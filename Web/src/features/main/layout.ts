// Pane widths of the main window (`MainWindowController.configureContent`). The
// file tree and the flow panel keep their widths; the source viewer takes the
// rest and never narrows below its minimum.

export const TREE_WIDTH = { initial: 300, min: 220 };
export const FLOW_WIDTH = { initial: 320, min: 260 };
export const SOURCE_MIN_WIDTH = 500;
export const DIVIDER_WIDTH = 6;

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), Math.max(min, max));
}

/**
 * The file tree width while its divider is dragged. `flow` is the flow panel's
 * width; the tree gives way before the source viewer drops below its minimum.
 */
export function clampTreeWidth(wanted: number, total: number, flow: number): number {
  const room = total - flow - SOURCE_MIN_WIDTH - 2 * DIVIDER_WIDTH;
  return clamp(wanted, TREE_WIDTH.min, room);
}

/**
 * The flow panel width while its divider is dragged. `left` is the width taken
 * by the file tree and its divider, or 0 while the tree is hidden.
 */
export function clampFlowWidth(wanted: number, total: number, left: number): number {
  const room = total - left - SOURCE_MIN_WIDTH - 2 * DIVIDER_WIDTH;
  return clamp(wanted, FLOW_WIDTH.min, room);
}
