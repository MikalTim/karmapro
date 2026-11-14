<script lang="ts">
  // The Bugs toolbar button with its red count (`BugBadgeView`). The count sits on
  // the icon's top-right corner, which the shared toolbar button cannot show as text.
  import { Bug } from "@lucide/svelte";
  import ToolbarButton from "../../lib/ui/ToolbarButton.svelte";
  import { bugBadgeText } from "./bugBadge";

  let { count, onClick }: { count: number; onClick: () => void } = $props();

  const badge = $derived(bugBadgeText(count));
</script>

<span class="bugs">
  <ToolbarButton
    label="Bugs"
    tooltip="Open the bug tracker to view, search, and create bug reports"
    {onClick}
  >
    {#snippet icon()}<span class="tint" style:color="var(--system-green)"><Bug size={16} /></span>{/snippet}
  </ToolbarButton>
  {#if badge !== null}<span class="badge">{badge}</span>{/if}
</span>

<style>
  .bugs {
    position: relative;
    display: inline-flex;
  }
  .tint {
    display: grid;
    place-items: center;
  }
  .badge {
    position: absolute;
    top: -6px;
    right: -6px;
    min-width: 18px;
    height: 18px;
    padding: 0 4px;
    box-sizing: border-box;
    border-radius: 9px;
    border: 1.5px solid var(--control-bg);
    background: var(--system-red);
    color: #fff;
    font-size: 10px;
    font-weight: 600;
    line-height: 15px;
    text-align: center;
    pointer-events: none;
  }
</style>
