<script lang="ts">
  // One line of text that is cut in the middle when it does not fit its box
  // (`NSLineBreakMode.byTruncatingMiddle`). The box takes the width the layout gives
  // it, and the text is measured in the font the box inherits. Runs of spaces are kept
  // as written, and a cut name shows in full as the tooltip, as a truncated label does.
  import { measureText } from "../../lib/diagram/measure";
  import { truncateMiddle } from "./middleTruncate";

  let { text }: { text: string } = $props();

  let box = $state<HTMLSpanElement>();
  let width = $state(0);
  let font = $state("");

  $effect(() => {
    if (box) font = getComputedStyle(box).font;
  });

  const shown = $derived(
    font === "" || width === 0 ? text : truncateMiddle(text, width, (candidate) => measureText(candidate, font)),
  );
</script>

<span class="box" bind:this={box} bind:clientWidth={width} title={shown === text ? undefined : text}>{shown}</span>

<style>
  .box {
    display: block;
    flex: 1;
    min-width: 0;
    overflow: hidden;
    white-space: pre;
  }
</style>
