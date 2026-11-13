<script lang="ts">
  // NSToolbar: a row of items with a flexible gap where `<Spacer />` would be.
  import type { Snippet } from "svelte";

  let { children }: { children: Snippet } = $props();
</script>

<div class="toolbar" role="toolbar">
  {@render children()}
</div>

<style>
  .toolbar {
    flex: none;
    display: flex;
    align-items: center;
    gap: 6px;
    height: 38px;
    padding: 0 10px;
    background: #323234;
    border-bottom: 1px solid rgba(0, 0, 0, 0.5);
  }
</style>
