<script lang="ts">
  // The Back and Forward toolbar buttons (`HistoryMenuButton`). A click goes one
  // file along; holding the button for half a second opens the recent files.
  import { ChevronLeft, ChevronRight } from "@lucide/svelte";
  import { showMenuAt, type MenuItem } from "../../lib/ui/contextMenu.svelte";

  let {
    direction,
    enabled,
    items,
    onClick,
  }: {
    direction: "back" | "forward";
    enabled: boolean;
    items: () => MenuItem[];
    onClick: () => void;
  } = $props();

  const HOLD_MS = 500;

  const tooltip = $derived(direction === "back" ? "Go back (hold for recent files)" : "Go forward (hold for recent files)");

  let button: HTMLButtonElement | undefined;
  let holdTimer: ReturnType<typeof setTimeout> | undefined;
  /** Set when the hold opened the menu, so the click that ends that press does nothing. */
  let heldOpen = false;

  function pressStart(event: PointerEvent): void {
    // A disabled button takes no mouse events, so holding it opens nothing.
    if (!enabled || event.button !== 0) return;
    heldOpen = false;
    clearTimeout(holdTimer);
    holdTimer = setTimeout(() => {
      if (!button) return;
      const rect = button.getBoundingClientRect();
      heldOpen = true;
      showMenuAt(rect.left, rect.bottom + 4, items());
    }, HOLD_MS);
  }

  function pressEnd(): void {
    clearTimeout(holdTimer);
  }

  function click(): void {
    if (heldOpen) {
      heldOpen = false;
      return;
    }
    if (enabled) onClick();
  }
</script>

<button
  bind:this={button}
  class="history"
  class:disabled={!enabled}
  aria-label={direction === "back" ? "Back" : "Forward"}
  aria-disabled={!enabled}
  title={tooltip}
  onpointerdown={pressStart}
  onpointerup={pressEnd}
  onpointerleave={pressEnd}
  onpointercancel={pressEnd}
  onclick={click}
>
  {#if direction === "back"}<ChevronLeft size={16} />{:else}<ChevronRight size={16} />{/if}
</button>

<style>
  .history {
    width: 32px;
    height: 28px;
    display: grid;
    place-items: center;
    background: none;
    border: 0;
    border-radius: 6px;
    color: var(--label);
    padding: 0;
  }
  .history:hover:not(.disabled) {
    background: rgba(255, 255, 255, 0.1);
  }
  .history.disabled {
    color: var(--tertiary-label);
  }
</style>
