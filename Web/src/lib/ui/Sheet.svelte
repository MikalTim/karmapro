<script lang="ts">
  // beginSheet: a panel attached to the top of a window that blocks that
  // window (and only that window) until it is dismissed.
  import type { Snippet } from "svelte";
  import { windowStore } from "./windows.svelte";

  let { windowId, width = 420, children }: { windowId: number; width?: number; children: Snippet } = $props();

  const win = $derived(windowStore.list.find((w) => w.id === windowId));
</script>

{#if win}
  <div class="scrim" style="left:{win.x}px; top:{win.y}px; width:{win.width}px; height:{win.height}px; z-index:{100 + win.z + 4000}">
    <div class="sheet" style="width:{Math.min(width, win.width - 24)}px">
      {@render children()}
    </div>
  </div>
{/if}

<style>
  .scrim {
    position: fixed;
    background: rgba(0, 0, 0, 0.25);
    display: flex;
    justify-content: center;
    align-items: flex-start;
    border-radius: 10px;
    overflow: hidden;
  }
  .sheet {
    margin-top: 28px;
    background: #3a3a3c;
    border-radius: 0 0 10px 10px;
    box-shadow: var(--shadow);
    padding: 16px;
    max-height: calc(100% - 28px);
    overflow: auto;
  }
</style>
