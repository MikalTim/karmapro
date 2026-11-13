<script lang="ts">
  // NSButton checkbox / switch.
  import type { Snippet } from "svelte";

  let {
    checked = $bindable(false),
    label,
    disabled = false,
    onChange,
    children,
  }: {
    checked?: boolean;
    label?: string;
    disabled?: boolean;
    onChange?: (checked: boolean) => void;
    children?: Snippet;
  } = $props();
</script>

<label class="checkbox" class:disabled>
  <input type="checkbox" bind:checked {disabled} onchange={() => onChange?.(checked)} />
  <span>{#if children}{@render children()}{:else}{label}{/if}</span>
</label>

<style>
  .checkbox {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
  .checkbox.disabled {
    color: var(--tertiary-label);
  }
  input {
    accent-color: var(--accent);
    margin: 0;
  }
</style>
