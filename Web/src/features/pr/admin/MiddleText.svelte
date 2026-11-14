<script lang="ts">
  // A table cell's text, shortened in the middle when it does not fit (`lineBreakMode = .byTruncatingMiddle`).
  import { measureText } from "../../../lib/diagram/measure";
  import { middleTruncate } from "./truncate";

  let { text, title }: { text: string; title?: string } = $props();

  let element: HTMLSpanElement | undefined = $state();
  let width = $state(0);

  const shown = $derived.by(() => {
    if (!element || width === 0) return text;
    const style = getComputedStyle(element);
    const font = `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    return middleTruncate(text, width, (candidate) => measureText(candidate, font));
  });
</script>

<span class="cell-text" bind:this={element} bind:clientWidth={width} {title}>{shown}</span>

<style>
  .cell-text {
    display: block;
    min-width: 0;
    overflow: hidden;
    white-space: nowrap;
  }
</style>
