<script lang="ts">
  // The main menu bar (Karma Pro, Edit, Licensing, Packages, Help) with the
  // pull-request status item at its right end.
  import type { Snippet } from "svelte";
  import MenuList from "./MenuList.svelte";
  import type { MenuItem } from "./contextMenu.svelte";

  export interface MenuDefinition {
    title: string;
    /** Called each time the menu opens, so enabled states and titles are current. */
    items: () => MenuItem[];
    bold?: boolean;
  }

  let { menus, right }: { menus: MenuDefinition[]; right?: Snippet } = $props();

  let openIndex = $state<number | null>(null);
  let bar: HTMLDivElement | undefined = $state();
  let current = $state<MenuItem[]>([]);

  function open(index: number) {
    current = menus[index].items();
    openIndex = index;
  }

  function outside(event: PointerEvent) {
    if (openIndex !== null && bar && !bar.contains(event.target as Node)) openIndex = null;
  }
</script>

<svelte:window onpointerdowncapture={outside} onblur={() => (openIndex = null)} />

<div class="bar" bind:this={bar} data-app-menu>
  {#each menus as menu, i (menu.title)}
    <div class="slot">
      <button
        class="title"
        class:bold={menu.bold}
        class:open={openIndex === i}
        onclick={() => (openIndex === i ? (openIndex = null) : open(i))}
        onmouseenter={() => openIndex !== null && open(i)}>{menu.title}</button
      >
      {#if openIndex === i}
        <div class="drop"><MenuList items={current} onPick={() => (openIndex = null)} /></div>
      {/if}
    </div>
  {/each}
  <div class="spacer"></div>
  {#if right}{@render right()}{/if}
</div>

<style>
  .bar {
    flex: none;
    display: flex;
    align-items: center;
    height: 24px;
    padding: 0 6px;
    background: #323234;
    border-bottom: 1px solid rgba(0, 0, 0, 0.5);
    position: relative;
    z-index: 70000;
  }
  .slot {
    position: relative;
  }
  .title {
    background: none;
    border: 0;
    padding: 2px 9px;
    border-radius: 4px;
    color: var(--label);
  }
  .title.bold {
    font-weight: 700;
  }
  .title.open,
  .title:hover {
    background: rgba(255, 255, 255, 0.14);
  }
  .drop {
    position: absolute;
    top: 100%;
    left: 0;
    z-index: 1;
  }
  .spacer {
    flex: 1;
  }
</style>
