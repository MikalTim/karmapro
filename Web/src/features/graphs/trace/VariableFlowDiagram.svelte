<script lang="ts">
  // The variable-flow canvas (`VariableFlowDiagramView`): the enclosing function's
  // flowchart with the callee boxes beside it. Drag a statement or a box to move
  // it, drag empty space to pan, ⌘/Ctrl-wheel or pinch to zoom, click a statement
  // or a use line to open it in the source viewer.
  import { DragTracker } from "../../../lib/diagram/drag";
  import { type Point, type ViewTransform, wheelZoomFactor, zoomAt } from "../../../lib/diagram/geometry";
  import { showFileInMainWindow } from "../../main/navigation";
  import type { VariableFlowDTO } from "./dto";
  import { browserFonts, browserMeasure } from "./text";
  import { EMPTY_LAYOUT, FLOW_FONT_SIZE, FLOW_NODE_WEIGHT, type Rect, type VariableLayout, layoutVariableFlow } from "./variableFlowLayout";
  import {
    MAX_SCALE,
    MIN_SCALE,
    type SceneItem,
    type SceneState,
    boxContentRect,
    buildVariableScene,
    fitView,
    flowNodeAt,
    flowNodeContentRect,
    rootBoxAt,
    tapAt,
  } from "./variableFlowScene";

  let { result }: { result: VariableFlowDTO | null } = $props();

  const IDENTITY: ViewTransform = { scale: 1, offsetX: 0, offsetY: 0 };
  /** NSView's click slop: a press that moves less than this is a click. */
  const CLICK_SLOP = 4;

  let container: HTMLDivElement | undefined = $state();
  let width = $state(0);
  let height = $state(0);

  const layout = $derived(
    result ? layoutVariableFlow(result, browserMeasure, browserFonts.ui(FLOW_FONT_SIZE, FLOW_NODE_WEIGHT)) : null,
  );

  /**
   * The user's changes to the layout. They belong to one layout, so a new trace
   * starts from the layout's own positions and a fitted view (`edits.layout`).
   */
  interface Edits {
    layout: VariableLayout | null;
    flow: Map<number, Point>;
    boxes: Map<string, Point>;
    /** Set once the user pans or zooms; until then the view is fitted to the window. */
    view: ViewTransform | null;
  }
  let edits = $state.raw<Edits>({ layout: null, flow: new Map(), boxes: new Map(), view: null });
  const active = $derived<Edits>(edits.layout === layout ? edits : { layout, flow: new Map(), boxes: new Map(), view: null });

  const transform = $derived<ViewTransform>(
    active.view ?? (layout ? fitView(layout.contentWidth, layout.contentHeight, width, height) : IDENTITY),
  );
  const sceneState = $derived<SceneState>({ flowPositions: active.flow, boxOffsets: active.boxes });
  const items = $derived<SceneItem[]>(
    buildVariableScene(layout ?? EMPTY_LAYOUT, sceneState, transform, layout !== null, browserFonts, browserMeasure),
  );

  function update(change: (next: Edits) => void): void {
    const base = active;
    const next: Edits = { layout, flow: new Map(base.flow), boxes: new Map(base.boxes), view: base.view };
    change(next);
    edits = next;
  }

  function localPoint(event: { clientX: number; clientY: number }): Point {
    const bounds = container?.getBoundingClientRect();
    return { x: event.clientX - (bounds?.left ?? 0), y: event.clientY - (bounds?.top ?? 0) };
  }

  // The gesture in progress; plain fields, because nothing draws from them.
  const tracker = new DragTracker();
  let pressPoint: Point = { x: 0, y: 0 };
  let moved = false;
  /** The callee boxes moved by a box drag: the root and everything inside its frame. */
  let draggedBoxes: { ids: string[]; startOffsets: Map<string, Point>; origin: Point } = {
    ids: [],
    startOffsets: new Map(),
    origin: { x: 0, y: 0 },
  };

  function pointerDown(event: PointerEvent): void {
    const current = layout;
    if (!current || event.button !== 0) return;
    const point = localPoint(event);
    pressPoint = point;
    moved = false;

    const flowID = flowNodeAt(point, current, sceneState, transform);
    if (flowID !== null) {
      const node = current.flowNodes.find((candidate) => candidate.id === flowID);
      const at = node ? flowNodeContentRect(node, sceneState) : null;
      tracker.down(point, `flow:${flowID}`, { x: at?.x ?? 0, y: at?.y ?? 0 }, transform);
    } else {
      const box = rootBoxAt(point, current, sceneState, transform);
      if (box) {
        const frame = boxContentRect(box, sceneState);
        const inside = current.boxes.filter((candidate) => contains(frame, boxContentRect(candidate, sceneState)));
        const startOffsets = new Map(inside.map((candidate) => [candidate.id, active.boxes.get(candidate.id) ?? { x: 0, y: 0 }]));
        draggedBoxes = { ids: inside.map((candidate) => candidate.id), startOffsets, origin: { x: frame.x, y: frame.y } };
        tracker.down(point, `box:${box.id}`, draggedBoxes.origin, transform);
      } else {
        // A press on empty space pans, and pinning the view stops the automatic fit.
        tracker.down(point, null, { x: 0, y: 0 }, transform);
        update((next) => {
          next.view = transform;
        });
      }
    }
    container?.setPointerCapture(event.pointerId);
  }

  function pointerMove(event: PointerEvent): void {
    const point = localPoint(event);
    if (Math.hypot(point.x - pressPoint.x, point.y - pressPoint.y) > CLICK_SLOP) moved = true;
    const change = tracker.move(point, transform.scale);
    if (!change) return;
    if ("offset" in change) {
      const offset = change.offset;
      update((next) => {
        next.view = { ...transform, offsetX: offset.x, offsetY: offset.y };
      });
    } else if (change.node.startsWith("flow:")) {
      const id = Number(change.node.slice("flow:".length));
      const position = change.position;
      update((next) => {
        next.flow.set(id, position);
      });
    } else {
      const dx = change.position.x - draggedBoxes.origin.x;
      const dy = change.position.y - draggedBoxes.origin.y;
      const moving = draggedBoxes;
      update((next) => {
        for (const id of moving.ids) {
          const start = moving.startOffsets.get(id) ?? { x: 0, y: 0 };
          next.boxes.set(id, { x: start.x + dx, y: start.y + dy });
        }
      });
    }
  }

  function pointerUp(event: PointerEvent): void {
    const clicked = tracker.up();
    const current = layout;
    if (moved || !current || !result) return;
    const point = localPoint(event);
    const tap = tapAt(point, current, sceneState, transform);
    if (tap) {
      showFileInMainWindow(tap.path, tap.line);
      return;
    }
    if (clicked?.startsWith("flow:")) {
      const id = Number(clicked.slice("flow:".length));
      const line = current.flowNodes.find((node) => node.id === id)?.line;
      const startPath = result.nodes.find((node) => node.isStart)?.path ?? result.nodes[0]?.path;
      if (line && startPath) showFileInMainWindow(startPath, line);
    }
  }

  // A non-passive listener, so preventDefault stops the page's own pinch zoom.
  $effect(() => {
    const element = container;
    if (!element) return;
    const onWheel = (event: WheelEvent) => {
      if (!(event.ctrlKey || event.metaKey)) return;
      event.preventDefault();
      const zoomed = zoomAt(transform, wheelZoomFactor(event.deltaY, event.deltaMode), localPoint(event), MIN_SCALE, MAX_SCALE);
      if (!zoomed) return;
      update((next) => {
        next.view = zoomed;
      });
    };
    element.addEventListener("wheel", onWheel, { passive: false });
    return () => element.removeEventListener("wheel", onWheel);
  });

  function contains(outer: Rect, inner: Rect): boolean {
    return (
      inner.x >= outer.x &&
      inner.y >= outer.y &&
      inner.x + inner.width <= outer.x + outer.width &&
      inner.y + inner.height <= outer.y + outer.height
    );
  }
</script>

<div
  class="diagram"
  bind:this={container}
  bind:clientWidth={width}
  bind:clientHeight={height}
  onpointerdown={pointerDown}
  onpointermove={pointerMove}
  onpointerup={pointerUp}
  onpointercancel={pointerUp}
  role="presentation"
>
  <svg {width} {height} aria-hidden="true">
    {#each items as item, index (index)}
      {#if item.shape === "path"}
        <path d={item.d} fill="none" style="stroke: {item.stroke}" stroke-width={item.width} />
      {:else if item.shape === "box"}
        <rect
          x={item.x}
          y={item.y}
          width={Math.max(item.width, 0)}
          height={Math.max(item.height, 0)}
          rx={item.radius}
          ry={item.radius}
          style="fill: {item.fill ?? 'none'}; fill-opacity: {item.fillOpacity ?? 1}; stroke: {item.stroke ?? 'none'}; stroke-opacity: {item.strokeOpacity ?? 1}"
          stroke-width={item.strokeWidth ?? 0}
        />
      {:else if item.shape === "oval"}
        <circle cx={item.cx} cy={item.cy} r={item.r} style="fill: {item.fill}" />
      {:else}
        <text
          x={item.x}
          y={item.y}
          text-anchor={item.anchor === "middle" ? "middle" : "start"}
          dominant-baseline="hanging"
          style="font: {item.font}; fill: {item.fill}; white-space: pre"
        >{item.text}</text>
      {/if}
    {/each}
  </svg>
</div>

<style>
  .diagram {
    position: relative;
    flex: 1;
    min-height: 0;
    overflow: hidden;
    background: var(--control-bg);
    touch-action: none;
  }
  svg {
    position: absolute;
    inset: 0;
  }
</style>
