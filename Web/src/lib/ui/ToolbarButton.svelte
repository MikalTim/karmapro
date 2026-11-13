<script lang="ts">
  // One NSToolbarItem button: an icon above a short label, with an optional badge.
  import type { Snippet } from "svelte";

  let {
    label,
    tooltip,
    onClick,
    disabled = false,
    badge = 0,
    pressed = false,
    icon,
    onContextMenu,
  }: {
    label?: string;
    tooltip?: string;
    onClick?: (event: MouseEvent) => void;
    disabled?: boolean;
    /** A red count badge (the Bugs button). Hidden at 0. */
    badge?: number;
    pressed?: boolean;
    icon: Snippet;
    onContextMenu?: (event: MouseEvent) => void;
  } = $props();
</script>

<button
  class="tool"
  class:pressed
  title={tooltip ?? label}
  {disabled}
  onclick={onClick}
  oncontextmenu={onContextMenu}
  aria-label={label}
>
  <span class="icon">{@render icon()}</span>
  {#if badge > 0}<span class="badge">{badge}</span>{/if}
</button>

<style>
  .tool {
    position: relative;
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
  .tool:hover:not(:disabled) {
    background: rgba(255, 255, 255, 0.1);
  }
  .tool.pressed {
    background: rgba(255, 255, 255, 0.18);
  }
  .tool:disabled {
    color: var(--tertiary-label);
  }
  .icon {
    display: grid;
    place-items: center;
  }
  .badge {
    position: absolute;
    top: -2px;
    right: -3px;
    min-width: 15px;
    height: 15px;
    padding: 0 4px;
    border-radius: 8px;
    background: var(--system-red);
    color: #fff;
    font-size: 10px;
    font-weight: 600;
    line-height: 15px;
    text-align: center;
  }
</style>
