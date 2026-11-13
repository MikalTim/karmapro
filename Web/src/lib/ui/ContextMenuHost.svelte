<script lang="ts">
  import MenuList from "./MenuList.svelte";
  import { closeContextMenu, contextMenu } from "./contextMenu.svelte";

  let element: HTMLDivElement | undefined = $state();
  let left = $state(0);
  let top = $state(0);

  // Keep the menu on the page: flip it up/left when it would overflow.
  $effect(() => {
    if (!contextMenu.open || !element) return;
    const width = element.offsetWidth;
    const height = element.offsetHeight;
    left = Math.max(0, Math.min(contextMenu.x, window.innerWidth - width - 4));
    top = Math.max(0, Math.min(contextMenu.y, window.innerHeight - height - 4));
  });

  function outside(event: PointerEvent) {
    if (contextMenu.open && element && !element.contains(event.target as Node)) closeContextMenu();
  }

  function keydown(event: KeyboardEvent) {
    if (contextMenu.open && event.key === "Escape") {
      event.stopPropagation();
      closeContextMenu();
    }
  }
</script>

<svelte:window onpointerdowncapture={outside} onkeydowncapture={keydown} onblur={closeContextMenu} />

{#if contextMenu.open}
  <div class="host" bind:this={element} style="left:{left}px; top:{top}px" oncontextmenu={(e) => e.preventDefault()} role="presentation">
    <MenuList items={contextMenu.items} onPick={closeContextMenu} />
  </div>
{/if}

<style>
  .host {
    position: fixed;
    z-index: 90000;
  }
</style>
