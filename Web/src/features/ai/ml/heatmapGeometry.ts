// The heatmap grid of `HeatmapView` as plain numbers: where each cell sits and
// how a flagged-line share becomes a colour. Every constant and formula is
// copied from `HeatmapView` in the Swift file.

const CELL_SIZE = 84;
const CAPTION_HEIGHT = 30;
const GAP = 10;
export const CORNER_RADIUS = 6;

const CAPTION_FONT = 11;
const CAPTION_FONT_SMALL = 9;
const CAPTION_OFFSET = 2;
/** The `--font-ui` stack, for canvas measurement (a canvas cannot read CSS variables). */
export const CAPTION_FONT_FAMILY = `-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif`;

const COLUMN_WIDTH = CELL_SIZE + GAP;
const ROW_HEIGHT = CELL_SIZE + CAPTION_HEIGHT + GAP;

export interface CellBox {
  x: number;
  y: number;
  size: number;
  /** Top of the file name under the cell. */
  captionY: number;
}

/** Number of columns that fit `width` (`HeatmapView.layoutContent`, at least one). */
export function columnCount(width: number): number {
  return Math.max(1, Math.floor((width - GAP) / COLUMN_WIDTH));
}

/** The height the grid needs for `count` cells; an empty grid still has one row. */
export function contentHeight(count: number, width: number): number {
  const rows = count === 0 ? 1 : Math.ceil(count / columnCount(width));
  return rows * ROW_HEIGHT + GAP;
}

/** Where cell `index` is drawn in a grid of `columns` columns. */
export function cellBox(index: number, columns: number): CellBox {
  const x = GAP + (index % columns) * COLUMN_WIDTH;
  const y = GAP + Math.floor(index / columns) * ROW_HEIGHT;
  return { x, y, size: CELL_SIZE, captionY: y + CELL_SIZE + CAPTION_OFFSET };
}

interface Rgb {
  r: number;
  g: number;
  b: number;
}

interface HeatStop {
  at: number;
  color: Rgb;
}

/**
 * The cold-to-hot ramp (blue → teal → green → yellow → red). Each Swift stop is
 * its 0...1 RGB value × 255, rounded.
 */
const HEAT_STOPS: HeatStop[] = [
  { at: 0.0, color: { r: 61, g: 99, b: 219 } },
  { at: 0.25, color: { r: 79, g: 189, b: 181 } },
  { at: 0.5, color: { r: 89, g: 199, b: 79 } },
  { at: 0.75, color: { r: 242, g: 199, b: 61 } },
  { at: 1.0, color: { r: 232, g: 61, b: 46 } },
];

function mix(a: Rgb, b: Rgb, f: number): Rgb {
  return { r: a.r + (b.r - a.r) * f, g: a.g + (b.g - a.g) * f, b: a.b + (b.b - a.b) * f };
}

function cssRgb(color: Rgb): string {
  return `rgb(${Math.round(color.r)}, ${Math.round(color.g)}, ${Math.round(color.b)})`;
}

/** The fill of a cell whose flagged share is `t` (0...1, clamped). */
export function heatColor(t: number): string {
  const clamped = Math.min(Math.max(t, 0), 1);
  let previous = HEAT_STOPS[0];
  for (const stop of HEAT_STOPS.slice(1)) {
    if (clamped <= stop.at) {
      return cssRgb(mix(previous.color, stop.color, (clamped - previous.at) / (stop.at - previous.at)));
    }
    previous = stop;
  }
  return cssRgb(previous.color);
}

/** The count is white on the hotter cells (intensity above 0.6), black otherwise. */
export function countTextColor(intensity: number): string {
  return intensity > 0.6 ? "#fff" : "#000";
}

export interface CaptionLayout {
  fontPx: number;
  text: string;
}

/**
 * The file name under a cell: 11 px when it fits the cell's width, else 9 px,
 * and middle-truncated to the cell's width at that size.
 */
export function captionLayout(name: string, measure: (text: string, fontPx: number) => number): CaptionLayout {
  const fontPx = measure(name, CAPTION_FONT) > CELL_SIZE - 4 ? CAPTION_FONT_SMALL : CAPTION_FONT;
  return { fontPx, text: truncateMiddle(name, CELL_SIZE, (text) => measure(text, fontPx)) };
}

/**
 * `.byTruncatingMiddle`: the longest text that keeps the start and end of
 * `text`, joined by “…”, and fits `maxWidth`. Returns `text` when it fits.
 */
export function truncateMiddle(text: string, maxWidth: number, measure: (text: string) => number): string {
  if (measure(text) <= maxWidth) return text;
  const ellipsis = "…";
  let best = ellipsis;
  let low = 0;
  let high = text.length;
  while (low <= high) {
    const keep = Math.floor((low + high) / 2);
    const head = Math.ceil(keep / 2);
    const candidate = text.slice(0, head) + ellipsis + text.slice(text.length - (keep - head));
    if (measure(candidate) <= maxWidth) {
      best = candidate;
      low = keep + 1;
    } else {
      high = keep - 1;
    }
  }
  return best;
}
