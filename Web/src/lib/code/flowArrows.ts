// Geometry of the control-flow arrows `ClickableTextView.drawFlowArrowsOverlay`
// draws over the source. Coordinates are those of the text view: x = 0 is the
// left edge of the text area (code starts at the 8 pt inset plus the 5 pt line
// fragment padding), y = 0 is the top of the first line's box. The spine lane
// sits at x = 2...6, left of every glyph.

export type FlowKind = "branchTrue" | "branchFalse" | "loopBack" | "rejoin" | "flow" | "exit";

export interface FlowArrow {
  fromLine: number;
  toLine: number;
  kind: FlowKind;
}

export interface ArrowShape {
  /** CSS colour. */
  color: string;
  /** The line to stroke, as an SVG path, or null for an exit chevron's shaft handled below. */
  stroke: { d: string; width: number; opacity: number } | null;
  /** The start dot, or null. */
  dot: { cx: number; cy: number; r: number } | null;
  /** The arrowhead polygon (SVG `points`). */
  head: string;
  fillOpacity: number;
}

const COLORS: Record<FlowKind, string> = {
  branchTrue: "var(--system-green)",
  branchFalse: "var(--system-red)",
  loopBack: "var(--system-blue)",
  rejoin: "var(--system-teal)",
  flow: "var(--system-gray)",
  exit: "var(--system-orange)",
};

/** Lane offsets per kind keep the true/false/loop/rejoin bows from collapsing onto one another. */
const LANES: Record<FlowKind, number> = {
  branchTrue: 0,
  branchFalse: 2,
  loopBack: 4,
  rejoin: 4,
  flow: 0,
  exit: 0,
};

/**
 * @param anchorY  Y of a line's vertical centre, or null when the line is not laid out.
 * @param textStartX X where a line's code begins (after its indentation).
 * @param visible  Only arrows that touch this y range are returned.
 */
export function arrowShapes(
  arrows: readonly FlowArrow[],
  anchorY: (line: number) => number | null,
  textStartX: (line: number) => number,
  visible?: { top: number; bottom: number },
): ArrowShape[] {
  const shapes: ArrowShape[] = [];
  for (const arrow of arrows) {
    const fromY = anchorY(arrow.fromLine);
    const toY = anchorY(arrow.toLine);
    if (fromY === null || toY === null) continue;
    if (visible && (Math.max(fromY, toY) < visible.top || Math.min(fromY, toY) > visible.bottom)) continue;
    const color = COLORS[arrow.kind];

    if (arrow.kind === "exit") {
      // A short right-pointing chevron marking a terminator line.
      const x = Math.max(textStartX(arrow.fromLine) - 12, 0);
      const tipX = x + 7;
      shapes.push({
        color,
        stroke: { d: `M${x} ${fromY}L${tipX - 4} ${fromY}`, width: 1.2, opacity: 0.9 },
        dot: null,
        head: `${tipX - 4},${fromY - 2.4} ${tipX},${fromY} ${tipX - 4},${fromY + 2.4}`,
        fillOpacity: 0.9,
      });
      continue;
    }

    if (Math.abs(toY - fromY) <= 2) continue;
    const fromX = Math.max(textStartX(arrow.fromLine) - 2, 0);
    const toX = Math.max(textStartX(arrow.toLine) - 2, 0);
    const laneX = 2 + LANES[arrow.kind];
    shapes.push({
      color,
      // One smooth S-bow: leave the source, hug the lane, arrive at the target.
      stroke: {
        d: `M${fromX} ${fromY}C${laneX} ${fromY} ${laneX} ${toY} ${toX} ${toY}`,
        width: arrow.kind === "flow" ? 1 : 1.3,
        opacity: 0.9,
      },
      dot: { cx: fromX, cy: fromY, r: 1.6 },
      // The bow ends horizontally, so the head points right.
      head: `${toX + 1},${toY} ${toX - 4},${toY - 2.6} ${toX - 4},${toY + 2.6}`,
      fillOpacity: 0.95,
    });
  }
  return shapes;
}

/** The SVG markup for `shapes`. Built only from numbers and fixed CSS variables. */
export function shapesToSvg(shapes: readonly ArrowShape[]): string {
  let svg = "";
  for (const shape of shapes) {
    if (shape.stroke) {
      svg += `<path d="${shape.stroke.d}" fill="none" stroke="${shape.color}" stroke-opacity="${shape.stroke.opacity}" stroke-width="${shape.stroke.width}"/>`;
    }
    if (shape.dot) {
      svg += `<circle cx="${shape.dot.cx}" cy="${shape.dot.cy}" r="${shape.dot.r}" fill="${shape.color}" fill-opacity="${shape.fillOpacity}"/>`;
    }
    svg += `<polygon points="${shape.head}" fill="${shape.color}" fill-opacity="${shape.fillOpacity}"/>`;
  }
  return svg;
}

/**
 * Columns taken by a line's leading spaces and tabs (a tab advances to the next
 * multiple of 4, like the editor's `tab-size`), so the overlay can place hooks
 * short of the first glyph.
 */
export function indentColumns(lineText: string): number {
  let columns = 0;
  for (const c of lineText) {
    if (c === " ") columns += 1;
    else if (c === "\t") columns += 4 - (columns % 4);
    else break;
  }
  return columns;
}
