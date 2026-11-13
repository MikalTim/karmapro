// Geometry shared by the diagram ports (`DataFlowDiagramView`, `FlowChartView`,
// `VariableFlowDiagramView`, `BacktraceDiagramView`). Every formula and constant
// is copied from the Swift views.

export interface Point {
  x: number;
  y: number;
}

/** Where the diagram is drawn: screen = content * scale + offset. */
export interface ViewTransform {
  scale: number;
  offsetX: number;
  offsetY: number;
}

/**
 * `orthogonalPath(from:to:lane:)`: down (or up) to a channel halfway between the
 * two nodes, across, then down to the end. `lane` shifts the channel so parallel
 * edges do not collapse onto one line. Returns the SVG path data.
 */
export function orthogonalPath(start: Point, end: Point, lane = 0): string {
  const channelY = (start.y + end.y) / 2 + lane;
  return `M${start.x} ${start.y}L${start.x} ${channelY}L${end.x} ${channelY}L${end.x} ${end.y}`;
}

/**
 * `drawArrowhead(from:to:)`: two strokes of length `length` leaving `to`, 0.4 rad
 * either side of the reverse direction. Returns the SVG path data (stroke it, 2 px wide).
 * DataFlowDiagramView uses length 9, BacktraceDiagramView 7.
 */
export function arrowheadPath(from: Point, to: Point, length = 9): string {
  const angle = Math.atan2(to.y - from.y, to.x - from.x);
  const left = { x: to.x - length * Math.cos(angle - 0.4), y: to.y - length * Math.sin(angle - 0.4) };
  const right = { x: to.x - length * Math.cos(angle + 0.4), y: to.y - length * Math.sin(angle + 0.4) };
  return `M${to.x} ${to.y}L${left.x} ${left.y}M${to.x} ${to.y}L${right.x} ${right.y}`;
}

/** `pointOnLine(_:_:distance:)`: the point `distance` from `from` towards `to`. */
export function pointOnLine(from: Point, to: Point, distance: number): Point {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const length = Math.hypot(dx, dy);
  if (length === 0) return from;
  return { x: from.x + (dx / length) * distance, y: from.y + (dy / length) * distance };
}

/**
 * `zoom(by:at:)`: scales by `factor`, clamped to [min, max], keeping the content
 * point under `at` where it is. Returns null when nothing changes.
 */
export function zoomAt(
  transform: ViewTransform,
  factor: number,
  at: Point,
  min: number,
  max: number,
): ViewTransform | null {
  if (!(factor > 0) || transform.scale === 0) return null;
  const scale = Math.max(min, Math.min(max, transform.scale * factor));
  if (scale === transform.scale || Number.isNaN(scale)) return null;
  const contentX = (at.x - transform.offsetX) / transform.scale;
  const contentY = (at.y - transform.offsetY) / transform.scale;
  return { scale, offsetX: at.x - contentX * scale, offsetY: at.y - contentY * scale };
}

/**
 * The zoom factor for a wheel event (⌘/Ctrl-scroll, or a pinch, which browsers
 * report as Ctrl + wheel): `max(0.2, min(3, 1 + delta / 60))`, where an
 * imprecise (line-based) wheel counts ten times as much. Scrolling up zooms in.
 */
export function wheelZoomFactor(deltaY: number, deltaMode: number): number {
  const delta = -deltaY * (deltaMode === 0 ? 1 : 10);
  return Math.max(0.2, Math.min(3, 1 + delta / 60));
}
