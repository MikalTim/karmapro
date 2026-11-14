<script lang="ts">
  // The focus-mode chip bar (AppKit `TunnelBar`): a title and one button per caller or callee, laid over the top
  // or the bottom of the source. A click moves the focus to that function, possibly in another file.
  import { measureText } from "../../lib/diagram/measure";
  import type { FocusChipDTO } from "./sourceApi";
  import { chipWidth } from "./sourceModel";
  import { monoFont } from "./viewerFont";

  let {
    kind,
    placement,
    items,
    onPick,
  }: {
    kind: "callers" | "callees";
    placement: "top" | "bottom";
    items: readonly FocusChipDTO[];
    onPick: (path: string, name: string) => void;
  } = $props();

  const chips = $derived(
    items.map((item) => ({ ...item, width: chipWidth(measureText(item.name, monoFont(11))) })),
  );
</script>

<div class="bar {placement}" role="toolbar" aria-label={kind}>
  <span class="title">{kind}:</span>
  {#each chips as chip, index (index)}
    <button class="chip" style="width:{chip.width}px" title={chip.path} onclick={() => onPick(chip.path, chip.name)}>
      {chip.name}
    </button>
  {/each}
</div>

<style>
  .bar {
    position: absolute;
    left: 12px;
    z-index: 2;
    display: flex;
    align-items: center;
    gap: 4px;
    height: 30px;
    max-width: calc(100% - 24px);
    padding: 0 10px;
    overflow-x: auto;
    box-sizing: border-box;
    border: 1px solid var(--separator);
    border-radius: 6px;
    background: color-mix(in srgb, var(--window-bg) 92%, transparent);
  }
  .bar.top {
    top: 8px;
  }
  .bar.bottom {
    bottom: 8px;
  }
  .title {
    margin-right: 6px;
    font-size: 11px;
    font-weight: 600;
    color: var(--secondary-label);
    white-space: nowrap;
  }
  .chip {
    flex: none;
    height: 22px;
    padding: 0 6px;
    box-sizing: border-box;
    font: 11px var(--font-mono);
    color: var(--label);
    white-space: nowrap;
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 5px;
    cursor: pointer;
  }
  .chip:hover {
    background: rgba(255, 255, 255, 0.18);
  }
</style>
