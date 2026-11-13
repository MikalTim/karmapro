// The mouse-down / drag / mouse-up state machine of the diagram views: a press
// on a node starts dragging it; a press on empty space pans the whole diagram.
// A press that never moves more than 4 px is a click on the node.
import type { Point, ViewTransform } from "./geometry";

const CLICK_SLOP = 4;

export type DragMode = "node" | "pan" | "none";

export class DragTracker {
  mode: DragMode = "none";
  /** The node being dragged, or the node a click would select. */
  nodeId: string | null = null;
  private clickNode: string | null = null;
  private startPoint: Point = { x: 0, y: 0 };
  private startNodePosition: Point = { x: 0, y: 0 };
  private startOffset: Point = { x: 0, y: 0 };

  /**
   * @param point screen point of the press
   * @param node the node under it, or null for empty space
   * @param nodePosition that node's layout position
   * @param transform the current view transform (the pan starts from its offset)
   */
  down(point: Point, node: string | null, nodePosition: Point, transform: ViewTransform): void {
    this.startPoint = point;
    this.clickNode = node;
    this.nodeId = node;
    if (node !== null) {
      this.mode = "node";
      this.startNodePosition = nodePosition;
    } else {
      this.mode = "pan";
      this.startOffset = { x: transform.offsetX, y: transform.offsetY };
    }
  }

  /** The node's new layout position while dragging a node, or the new view offset while panning; null otherwise. */
  move(point: Point, scale: number): { node: string; position: Point } | { offset: Point } | null {
    if (this.mode === "none") return null;
    const dx = point.x - this.startPoint.x;
    const dy = point.y - this.startPoint.y;
    if (this.mode === "node" && this.nodeId !== null) {
      // Any movement past the slop cancels the pending click.
      if (Math.hypot(dx, dy) > CLICK_SLOP) this.clickNode = null;
      return {
        node: this.nodeId,
        position: { x: this.startNodePosition.x + dx / scale, y: this.startNodePosition.y + dy / scale },
      };
    }
    return { offset: { x: this.startOffset.x + dx, y: this.startOffset.y + dy } };
  }

  /** Ends the gesture. Returns the clicked node, or null when it was a drag or a pan. */
  up(): string | null {
    const clicked = this.clickNode;
    this.mode = "none";
    this.nodeId = null;
    this.clickNode = null;
    return clicked;
  }
}
