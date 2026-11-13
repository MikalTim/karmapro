<script lang="ts">
  // NSPopover (transient): shown next to an anchor rectangle, closed by a
  // click outside it or Esc.
  import type { Snippet } from "svelte";

  let {
    anchor,
    width,
    height,
    onClose,
    children,
  }: {
    /** The rectangle (viewport coordinates) the popover points at. */
    anchor: { x: number; y: number; width: number; height: number };
    width: number;
    height?: number;
    onClose: () => void;
    children: Snippet;
  } = $props();

  let element: HTMLDivElement | undefined = $state();

  const position = $derived.by(() => {
    const below = anchor.y + anchor.height + 8;
    const fitsBelow = below + (height ?? 200) < window.innerHeight;
    return {
      left: Math.max(4, Math.min(anchor.x + anchor.width / 2 - width / 2, window.innerWidth - width - 4)),
      top: fitsBelow ? below : Math.max(4, anchor.y - (height ?? 200) - 8),
    };
  });

  function outside(event: PointerEvent) {
    if (element && !element.contains(event.target as Node)) onClose();
  }

  function keydown(event: KeyboardEvent) {
    if (event.key === "Escape") {
      event.stopPropagation();
      onClose();
    }
  }
</script>

<svelte:window onpointerdowncapture={outside} onkeydowncapture={keydown} />

<div
  class="popover"
  bind:this={element}
  style="left:{position.left}px; top:{position.top}px; width:{width}px; {height ? `height:${height}px;` : ''}"
  role="dialog"
>
  {@render children()}
</div>

<style>
  .popover {
    position: fixed;
    z-index: 80000;
    background: #3a3a3c;
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 8px;
    box-shadow: var(--shadow);
    padding: 10px;
    display: flex;
    flex-direction: column;
  }
</style>
