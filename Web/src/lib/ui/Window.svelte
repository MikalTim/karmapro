<script lang="ts">
  import type { Snippet } from "svelte";
  import { X } from "@lucide/svelte";
  import {
    WINDOW_TITLE_BAR,
    closeWindow,
    focusWindow,
    moveWindow,
    resizeWindow,
    topWindowId,
    windowStore,
    type WindowState,
  } from "./windows.svelte";

  let { win, children }: { win: WindowState; children: Snippet } = $props();

  type Edge = "n" | "s" | "e" | "w" | "ne" | "nw" | "se" | "sw";

  function startDrag(event: PointerEvent) {
    if (event.button !== 0) return;
    if ((event.target as HTMLElement).closest("button")) return;
    const startX = event.clientX - win.x;
    const startY = event.clientY - win.y;
    const target = event.currentTarget as HTMLElement;
    target.setPointerCapture(event.pointerId);
    const move = (e: PointerEvent) => moveWindow(win.id, e.clientX - startX, e.clientY - startY);
    const up = () => {
      target.removeEventListener("pointermove", move);
      target.removeEventListener("pointerup", up);
    };
    target.addEventListener("pointermove", move);
    target.addEventListener("pointerup", up);
  }

  function startResize(edge: Edge, event: PointerEvent) {
    event.preventDefault();
    event.stopPropagation();
    focusWindow(win.id);
    const origin = { x: win.x, y: win.y, w: win.width, h: win.height, px: event.clientX, py: event.clientY };
    const target = event.currentTarget as HTMLElement;
    target.setPointerCapture(event.pointerId);
    const move = (e: PointerEvent) => {
      const dx = e.clientX - origin.px;
      const dy = e.clientY - origin.py;
      let { x, y, w, h } = origin;
      if (edge.includes("e")) w = origin.w + dx;
      if (edge.includes("s")) h = origin.h + dy;
      if (edge.includes("w")) {
        w = origin.w - dx;
        x = origin.x + dx;
      }
      if (edge.includes("n")) {
        h = origin.h - dy;
        y = origin.y + dy;
      }
      resizeWindow(win.id, x, y, w, h);
      // When the minimum size stopped the resize, keep the opposite edge anchored.
      if (edge.includes("w")) win.x = origin.x + origin.w - win.width;
      if (edge.includes("n")) win.y = origin.y + origin.h - win.height;
    };
    const up = () => {
      target.removeEventListener("pointermove", move);
      target.removeEventListener("pointerup", up);
    };
    target.addEventListener("pointermove", move);
    target.addEventListener("pointerup", up);
  }

  /**
   * Escape goes to the window that has the focus. A key typed in the main window's panes belongs to the main
   * window; everywhere else (the toolbar button that just opened this window, the body) it is for the top window.
   */
  function escapeIsForWindows(event: KeyboardEvent): boolean {
    const target = event.target;
    return !(target instanceof Element) || target.closest("[data-main-panes]") === null;
  }

  function keydown(event: KeyboardEvent) {
    const closes = event.key === "Escape" && win.spec.escCloses && topWindowId() === win.id;
    if (closes && !event.defaultPrevented && escapeIsForWindows(event)) {
      event.stopPropagation();
      void closeWindow(win.id);
    }
  }

  const edges: Edge[] = ["n", "s", "e", "w", "ne", "nw", "se", "sw"];
  const active = $derived(windowStore.top === win.z);
</script>

<svelte:window onkeydown={keydown} />

<div
  class="window"
  class:active
  role="dialog"
  aria-label={win.title}
  tabindex="-1"
  style="left:{win.x}px; top:{win.y}px; width:{win.width}px; height:{win.height}px; z-index:{100 + win.z};"
  onpointerdown={() => focusWindow(win.id)}
>
  <div class="title-bar" style="height:{WINDOW_TITLE_BAR}px" onpointerdown={startDrag} role="presentation">
    <button class="close" title="Close" aria-label="Close" onclick={() => closeWindow(win.id)}>
      <X size={10} strokeWidth={3} />
    </button>
    <div class="title">{win.title}</div>
  </div>
  <div class="content">
    {@render children()}
  </div>
  {#each edges as edge (edge)}
    <div class="edge {edge}" onpointerdown={(e) => startResize(edge, e)} role="presentation"></div>
  {/each}
</div>

<style>
  .window {
    position: fixed;
    display: flex;
    flex-direction: column;
    background: var(--window-bg);
    border-radius: 10px;
    box-shadow: var(--shadow);
    overflow: hidden;
  }
  .window:not(.active) .title {
    color: var(--secondary-label);
  }
  .title-bar {
    flex: none;
    display: flex;
    align-items: center;
    background: var(--title-bar);
    border-bottom: 1px solid rgba(0, 0, 0, 0.5);
    position: relative;
    cursor: default;
  }
  .title {
    position: absolute;
    inset: 0 60px;
    text-align: center;
    line-height: 28px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    pointer-events: none;
  }
  .close {
    position: relative;
    z-index: 1;
    margin-left: 8px;
    width: 13px;
    height: 13px;
    padding: 0;
    border-radius: 50%;
    border: 0;
    background: #ff5f57;
    color: transparent;
    display: grid;
    place-items: center;
  }
  .close:hover {
    color: rgba(0, 0, 0, 0.6);
  }
  .window:not(.active) .close {
    background: #5a5a5c;
  }
  .content {
    flex: 1;
    min-height: 0;
    position: relative;
    display: flex;
    flex-direction: column;
  }
  .edge {
    position: absolute;
    z-index: 5;
  }
  .n,
  .s {
    left: 8px;
    right: 8px;
    height: 5px;
    cursor: ns-resize;
  }
  .e,
  .w {
    top: 8px;
    bottom: 8px;
    width: 5px;
    cursor: ew-resize;
  }
  .n { top: 0; }
  .s { bottom: 0; }
  .e { right: 0; }
  .w { left: 0; }
  .ne, .nw, .se, .sw {
    width: 10px;
    height: 10px;
  }
  .ne { top: 0; right: 0; cursor: nesw-resize; }
  .nw { top: 0; left: 0; cursor: nwse-resize; }
  .se { bottom: 0; right: 0; cursor: nwse-resize; }
  .sw { bottom: 0; left: 0; cursor: nesw-resize; }
</style>
