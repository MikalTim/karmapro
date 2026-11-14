<script lang="ts">
  // The hover type tooltip (AppKit `ClickableTextView.showTypeTooltip`): the type of the identifier under the
  // pointer, in a small panel above the identifier, or below it when there is no room above. A press anywhere
  // closes it, as a transient popover does.
  import { measureText } from "../../lib/diagram/measure";
  import { TYPE_TOOLTIP_HEIGHT, type ViewportRect, typeTooltipWidth } from "./sourceModel";
  import { monoFont } from "./viewerFont";

  let {
    text,
    anchor,
    onClose,
  }: {
    text: string;
    anchor: ViewportRect;
    onClose: () => void;
  } = $props();

  const GAP = 6;
  const width = $derived(typeTooltipWidth(measureText(text, monoFont(12))));
  const roomAbove = $derived(anchor.y - TYPE_TOOLTIP_HEIGHT - GAP >= 4);
  const top = $derived(roomAbove ? anchor.y - TYPE_TOOLTIP_HEIGHT - GAP : anchor.y + anchor.height + GAP);
  const left = $derived(Math.max(4, Math.min(anchor.x, window.innerWidth - width - 4)));
</script>

<svelte:window onpointerdowncapture={onClose} />

<div class="tooltip" style="left:{left}px; top:{top}px; width:{width}px; height:{TYPE_TOOLTIP_HEIGHT}px">{text}</div>

<style>
  .tooltip {
    position: fixed;
    z-index: 80000;
    box-sizing: border-box;
    display: flex;
    align-items: center;
    padding: 0 10px;
    background: #3a3a3c;
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 8px;
    box-shadow: var(--shadow);
    font: 12px var(--font-mono);
    color: var(--secondary-label);
    white-space: nowrap;
    overflow: hidden;
    pointer-events: none;
  }
</style>
