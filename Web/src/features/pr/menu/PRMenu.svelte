<script lang="ts">
  // The pull request status item at the right end of the menu bar (`PRMenuBarController`). Its menu is rebuilt
  // from the shared state each time it opens, so its items are never older than the last change.
  import { GitPullRequest } from "@lucide/svelte";
  import { runMenuAction } from "./menuActions";
  import { buildPRMenu, statusAccessibilityLabel, statusTooltip, type PRMenuAction, type PRMenuEntry } from "./menuModel";
  import { reviewState } from "./review.svelte";

  let open = $state(false);
  let root: HTMLDivElement | undefined = $state();

  const current = $derived(reviewState.value);
  const monitoring = $derived(current?.monitoringEnabled ?? false);
  const entries = $derived<PRMenuEntry[]>(current ? buildPRMenu(current) : []);
  const apple = typeof navigator !== "undefined" && /Mac|iPhone|iPad|iPod/.test(navigator.platform);

  function shortcutText(key: string): string {
    return apple ? `\u2318${key.toUpperCase()}` : `Ctrl+${key.toUpperCase()}`;
  }

  function choose(action: PRMenuAction) {
    open = false;
    void runMenuAction(action);
  }

  function outside(event: PointerEvent) {
    if (open && root && !(event.target instanceof Node && root.contains(event.target))) open = false;
  }

  function keydown(event: KeyboardEvent) {
    if (open && event.key === "Escape") open = false;
  }
</script>

<svelte:window onpointerdowncapture={outside} onkeydown={keydown} />

<div class="pr-menu" bind:this={root}>
  <button
    class="status"
    class:on={monitoring}
    title={statusTooltip(monitoring)}
    aria-label={statusAccessibilityLabel(monitoring)}
    aria-haspopup="menu"
    aria-expanded={open}
    onclick={() => (open = !open)}
  >
    <GitPullRequest size={16} strokeWidth={2} />
  </button>
  {#if open && current}
    <div class="drop" role="menu">
      {#each entries as entry, i (i)}
        {#if entry.kind === "separator"}
          <hr class="separator" />
        {:else if entry.kind === "label"}
          <div class="label" class:indented={entry.indented}>{entry.title}</div>
        {:else}
          <button
            class="item"
            class:indented={entry.indented}
            role="menuitem"
            title={entry.tooltip}
            onclick={() => choose(entry.action)}
          >
            <span class="check">{entry.checked ? "\u2713" : ""}</span>
            <span class="text">{entry.title}</span>
            {#if entry.keyEquivalent}<span class="shortcut">{shortcutText(entry.keyEquivalent)}</span>{/if}
          </button>
        {/if}
      {/each}
    </div>
  {/if}
</div>

<style>
  .pr-menu {
    position: relative;
    display: flex;
    align-items: center;
  }
  .status {
    display: flex;
    align-items: center;
    background: none;
    border: 0;
    padding: 2px 8px;
    border-radius: 4px;
    color: var(--label);
    /* Faded while monitoring is off: present, but plainly not working. */
    opacity: 0.55;
    cursor: default;
  }
  .status.on {
    color: var(--system-blue);
    opacity: 1;
  }
  .status:hover,
  .status[aria-expanded="true"] {
    background: rgba(255, 255, 255, 0.14);
  }
  .drop {
    position: absolute;
    top: 100%;
    right: 0;
    z-index: 1;
    min-width: 240px;
    background: var(--title-bar);
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 7px;
    box-shadow: var(--shadow);
    padding: 4px;
  }
  .item {
    display: flex;
    align-items: center;
    gap: 6px;
    width: 100%;
    background: none;
    border: 0;
    border-radius: 4px;
    padding: 2px 10px 2px 4px;
    color: var(--label);
    text-align: left;
    white-space: nowrap;
    cursor: default;
  }
  .item.indented,
  .label.indented {
    padding-left: 22px;
  }
  .item:hover {
    background: var(--accent);
    color: #fff;
  }
  .item:hover .shortcut {
    color: rgba(255, 255, 255, 0.8);
  }
  .check {
    width: 14px;
    text-align: center;
  }
  .text {
    flex: 1;
  }
  .shortcut {
    color: var(--secondary-label);
    margin-left: 24px;
  }
  .label {
    padding: 2px 10px 2px 4px;
    color: var(--tertiary-label);
    white-space: nowrap;
  }
</style>
