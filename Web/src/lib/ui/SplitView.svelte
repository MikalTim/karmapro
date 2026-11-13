<script lang="ts">
  // NSSplitView: two panes with a draggable divider. `size` is the first
  // pane's size in px along the split axis; the second pane takes the rest.
  import type { Snippet } from "svelte";

  let {
    vertical = false,
    size = $bindable(240),
    minFirst = 120,
    minSecond = 160,
    collapsed = false,
    first,
    second,
  }: {
    /** True stacks the panes top/bottom (a horizontal divider). */
    vertical?: boolean;
    size?: number;
    minFirst?: number;
    minSecond?: number;
    /** Hides the first pane (the sidebar toggle). */
    collapsed?: boolean;
    first: Snippet;
    second: Snippet;
  } = $props();

  let host: HTMLDivElement | undefined = $state();

  function drag(event: PointerEvent) {
    event.preventDefault();
    const target = event.currentTarget as HTMLElement;
    target.setPointerCapture(event.pointerId);
    const start = vertical ? event.clientY : event.clientX;
    const startSize = size;
    const move = (e: PointerEvent) => {
      const total = vertical ? (host?.clientHeight ?? 0) : (host?.clientWidth ?? 0);
      const wanted = startSize + (vertical ? e.clientY : e.clientX) - start;
      size = Math.min(Math.max(wanted, minFirst), Math.max(minFirst, total - minSecond - 6));
    };
    const up = () => {
      target.removeEventListener("pointermove", move);
      target.removeEventListener("pointerup", up);
    };
    target.addEventListener("pointermove", move);
    target.addEventListener("pointerup", up);
  }
</script>

<div class="split" class:vertical bind:this={host}>
  {#if !collapsed}
    <div class="pane first" style={vertical ? `height:${size}px` : `width:${size}px`}>
      {@render first()}
    </div>
    <div class="divider" role="separator" aria-orientation={vertical ? "horizontal" : "vertical"} onpointerdown={drag}></div>
  {/if}
  <div class="pane second">
    {@render second()}
  </div>
</div>

<style>
  .split {
    display: flex;
    flex: 1;
    min-height: 0;
    min-width: 0;
  }
  .split.vertical {
    flex-direction: column;
  }
  .pane {
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
    overflow: hidden;
  }
  .first {
    flex: none;
  }
  .second {
    flex: 1;
  }
  .divider {
    flex: none;
    width: 6px;
    cursor: col-resize;
    background: linear-gradient(to right, transparent 2px, rgba(0, 0, 0, 0.6) 2px, rgba(0, 0, 0, 0.6) 3px, transparent 3px);
  }
  .vertical > .divider {
    width: auto;
    height: 6px;
    cursor: row-resize;
    background: linear-gradient(to bottom, transparent 2px, rgba(0, 0, 0, 0.6) 2px, rgba(0, 0, 0, 0.6) 3px, transparent 3px);
  }
</style>
