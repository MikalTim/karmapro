<script lang="ts">
  // The items of one menu, shared by context menus and the menu bar.
  import Self from "./MenuList.svelte";
  import type { MenuItem } from "./contextMenu.svelte";

  let { items, onPick }: { items: MenuItem[]; onPick: () => void } = $props();

  let openSub = $state<number | null>(null);

  function choose(item: MenuItem) {
    if (item.disabled || item.submenu) return;
    onPick();
    item.action?.();
  }
</script>

<div class="menu" role="menu">
  {#each items as item, i (i)}
    {#if item.separator}
      <hr class="separator" />
    {:else}
      <div
        class="item"
        class:disabled={item.disabled}
        role="menuitem"
        tabindex="-1"
        onclick={() => choose(item)}
        onkeydown={(e) => e.key === "Enter" && choose(item)}
        onmouseenter={() => (openSub = item.submenu ? i : null)}
      >
        <span class="check">{item.checked ? "✓" : ""}</span>
        <span class="title">{item.title}</span>
        {#if item.shortcut}<span class="shortcut">{item.shortcut}</span>{/if}
        {#if item.submenu}<span class="arrow">▸</span>{/if}
        {#if item.submenu && openSub === i}
          <div class="sub"><Self items={item.submenu} {onPick} /></div>
        {/if}
      </div>
    {/if}
  {/each}
</div>

<style>
  .menu {
    min-width: 180px;
    background: #3a3a3c;
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 7px;
    box-shadow: var(--shadow);
    padding: 4px;
  }
  .item {
    position: relative;
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 2px 10px 2px 4px;
    border-radius: 4px;
    white-space: nowrap;
  }
  .item:hover:not(.disabled) {
    background: var(--accent);
    color: #fff;
  }
  .item.disabled {
    color: var(--tertiary-label);
  }
  .check {
    width: 14px;
    text-align: center;
  }
  .title {
    flex: 1;
  }
  .shortcut {
    color: var(--secondary-label);
    margin-left: 24px;
  }
  .item:hover:not(.disabled) .shortcut {
    color: rgba(255, 255, 255, 0.8);
  }
  .sub {
    position: absolute;
    left: 100%;
    top: -5px;
    z-index: 1;
  }
</style>
