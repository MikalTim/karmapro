// A Svelte action that gives a diagram `<svg>` the AppKit views' navigation:
// drag empty space to pan, ⌘/Ctrl-scroll or pinch to zoom around the pointer.
// Plain scrolling is left alone so the surrounding page still scrolls (the
// Swift views ignore it for the same reason).
import { DragTracker } from "./drag";
import { type Point, type ViewTransform, wheelZoomFactor, zoomAt } from "./geometry";

export interface PanZoomOptions {
  transform: () => ViewTransform;
  /** Called with the new transform; the diagram then re-renders. */
  setTransform: (transform: ViewTransform) => void;
  minScale: number;
  maxScale: number;
  /** The node under a screen point (relative to the element), or null. */
  nodeAt: (point: Point) => string | null;
  /** The layout position of a node. */
  nodePosition: (node: string) => Point;
  /** A node was dragged to a new layout position. */
  onNodeMove: (node: string, position: Point) => void;
  /** A node was clicked without being dragged. */
  onNodeClick: (node: string) => void;
  /** The user zoomed or panned, so an automatic re-fit must stop overriding the view (`hasUserViewTransform`). */
  onUserTransform?: () => void;
  /** Press handled elsewhere (for example a ⊕ badge)? Return true to skip the drag. */
  onPress?: (point: Point) => boolean;
}

export function panZoom(element: Element, initial: PanZoomOptions) {
  let options = initial;
  const tracker = new DragTracker();

  function local(event: MouseEvent | WheelEvent): Point {
    const box = element.getBoundingClientRect();
    return { x: event.clientX - box.left, y: event.clientY - box.top };
  }

  function pointerdown(event: Event) {
    if (!(event instanceof PointerEvent) || event.button !== 0) return;
    const point = local(event);
    if (options.onPress?.(point)) return;
    const node = options.nodeAt(point);
    tracker.down(point, node, node === null ? { x: 0, y: 0 } : options.nodePosition(node), options.transform());
    if (node === null) options.onUserTransform?.();
    element.setPointerCapture(event.pointerId);
    // closedHand while dragging a node, openHand while panning.
    (element as HTMLElement).style.cursor = node === null ? "grab" : "grabbing";
  }

  function pointermove(event: Event) {
    if (!(event instanceof PointerEvent)) return;
    const moved = tracker.move(local(event), options.transform().scale);
    if (moved === null) return;
    if ("node" in moved) options.onNodeMove(moved.node, moved.position);
    else options.setTransform({ ...options.transform(), offsetX: moved.offset.x, offsetY: moved.offset.y });
  }

  function pointerup(event: Event) {
    if (!(event instanceof PointerEvent)) return;
    const clicked = tracker.up();
    if (element.hasPointerCapture(event.pointerId)) element.releasePointerCapture(event.pointerId);
    (element as HTMLElement).style.cursor = "";
    if (clicked !== null) options.onNodeClick(clicked);
  }

  function wheel(event: Event) {
    if (!(event instanceof WheelEvent) || !(event.ctrlKey || event.metaKey)) return;
    event.preventDefault();
    const next = zoomAt(
      options.transform(),
      wheelZoomFactor(event.deltaY, event.deltaMode),
      local(event),
      options.minScale,
      options.maxScale,
    );
    if (next === null) return;
    options.onUserTransform?.();
    options.setTransform(next);
  }

  element.addEventListener("pointerdown", pointerdown);
  element.addEventListener("pointermove", pointermove);
  element.addEventListener("pointerup", pointerup);
  element.addEventListener("pointercancel", pointerup);
  // Not passive: a zoom must stop the page from zooming too.
  element.addEventListener("wheel", wheel, { passive: false });

  return {
    update(next: PanZoomOptions) {
      options = next;
    },
    destroy() {
      element.removeEventListener("pointerdown", pointerdown);
      element.removeEventListener("pointermove", pointermove);
      element.removeEventListener("pointerup", pointerup);
      element.removeEventListener("pointercancel", pointerup);
      element.removeEventListener("wheel", wheel);
    },
  };
}
