// The complexity scatter's geometry, colours and labels, ported from
// `ComplexityScatterView`. Positions are in the view's own px with the origin at
// the top left (AppKit draws from the bottom; the arithmetic is the same).
import type { Point } from "../../../lib/diagram/geometry";
import type { ComplexityPointDTO } from "./dto";

export interface PlotRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

/** `leftMargin`, `rightMargin`, `topMargin`, `bottomMargin`. */
const MARGIN = { left: 46, right: 24, top: 18, bottom: 40 } as const;

/** Distances within which a press or a hover finds a point (`pointIndex(near:tolerance:)`). */
export const HOVER_TOLERANCE = 14;
export const CLICK_TOLERANCE = 18;

/** The dot radius, the hover halo radius, and the label distance that keeps labels apart. */
export const DOT_RADIUS = 9;
export const HALO_RADIUS = 12;
const LABEL_GAP_X = 22;
const LABEL_GAP_Y = 12;

export function plotRect(width: number, height: number): PlotRect {
  return {
    left: MARGIN.left,
    top: MARGIN.top,
    width: Math.max(width - MARGIN.left - MARGIN.right, 10),
    height: Math.max(height - MARGIN.top - MARGIN.bottom, 10),
  };
}

/** The highest complexity, at least 1 (`chartGeometry`). */
export function maxComplexity(points: readonly ComplexityPointDTO[]): number {
  return points.reduce((highest, point) => Math.max(highest, point.complexity), 1);
}

/** X is the function's place in the source order, Y its complexity. */
export function pointPosition(index: number, count: number, complexity: number, maxC: number, plot: PlotRect): Point {
  const x = count > 1 ? plot.left + (index / (count - 1)) * plot.width : plot.left + plot.width / 2;
  const y = plot.top + plot.height - (complexity / maxC) * plot.height;
  return { x, y };
}

/** The Y-axis ticks: 0, a step, and so on up to the highest complexity. */
export function yTicks(maxC: number): number[] {
  const step = Math.max(1, Math.ceil(maxC / 6));
  const ticks: number[] = [];
  for (let value = 0; value <= maxC; value += step) ticks.push(value);
  return ticks;
}

const COLOR_STOPS: Array<{ at: number; rgb: [number, number, number] }> = [
  { at: 0, rgb: [0.18, 0.65, 0.22] },
  { at: 0.5, rgb: [0.95, 0.8, 0.2] },
  { at: 1, rgb: [0.85, 0.18, 0.12] },
];

/** Green, then yellow, then red as the complexity approaches the maximum, as a hex colour. */
export function complexityColor(complexity: number, maxC: number): string {
  const t = Math.min(Math.max(complexity / maxC, 0), 1);
  for (let index = 0; index < COLOR_STOPS.length - 1; index++) {
    const from = COLOR_STOPS[index];
    const to = COLOR_STOPS[index + 1];
    if (t < from.at || t > to.at) continue;
    const u = (t - from.at) / (to.at - from.at);
    const channels = from.rgb.map((value, channel) => Math.round((value + (to.rgb[channel] - value) * u) * 255));
    return `#${channels.map((value) => value.toString(16).padStart(2, "0")).join("")}`;
  }
  return "#ff453a";
}

/** The index of the point nearest `point` within `tolerance`; on a tie the later point wins. */
export function pointIndexAt(point: Point, positions: readonly Point[], tolerance: number): number | null {
  let best: number | null = null;
  let bestDistance = tolerance * tolerance;
  for (let index = 0; index < positions.length; index++) {
    const dx = positions[index].x - point.x;
    const dy = positions[index].y - point.y;
    const distance = dx * dx + dy * dy;
    if (distance <= bestDistance) {
      bestDistance = distance;
      best = index;
    }
  }
  return best;
}

/**
 * Which points carry their number. The hovered one always does; others are
 * skipped when they sit too close to the last labelled point to read.
 */
export function labelledPoints(positions: readonly Point[], hovered: number | null): boolean[] {
  const shows: boolean[] = [];
  let last: Point | null = null;
  for (let index = 0; index < positions.length; index++) {
    const position = positions[index];
    const shown =
      index === hovered ||
      last === null ||
      Math.abs(position.x - last.x) >= LABEL_GAP_X ||
      Math.abs(position.y - last.y) >= LABEL_GAP_Y;
    if (shown) last = position;
    shows.push(shown);
  }
  return shows;
}

/** The last path component, as `lastPathComponent` gives it. */
export function baseName(path: string): string {
  return path.slice(path.lastIndexOf("/") + 1);
}

/** The line shown under the chart while a point is hovered. */
export function hoverText(point: ComplexityPointDTO): string {
  return `${baseName(point.path)} · ${point.name} — line ${point.line} · complexity ${point.complexity}`;
}
