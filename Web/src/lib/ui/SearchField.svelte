<script lang="ts">
  // NSSearchField: filters on every keystroke (controlTextDidChange), has a
  // clear button, and reports Enter.
  import { Search, CircleX } from "@lucide/svelte";

  let {
    value = $bindable(""),
    placeholder = "Search",
    width,
    onInput,
    onEnter,
    focusOnMount = false,
  }: {
    value?: string;
    placeholder?: string;
    width?: number;
    onInput?: (value: string) => void;
    onEnter?: (shift: boolean) => void;
    focusOnMount?: boolean;
  } = $props();

  let input: HTMLInputElement | undefined = $state();

  $effect(() => {
    if (focusOnMount) input?.focus();
  });

  export function focus() {
    input?.focus();
    input?.select();
  }
</script>

<div class="search" style={width ? `width:${width}px` : undefined}>
  <Search size={12} class="glass" />
  <input
    bind:this={input}
    type="text"
    {placeholder}
    bind:value
    oninput={() => onInput?.(value)}
    onkeydown={(e) => e.key === "Enter" && onEnter?.(e.shiftKey)}
    spellcheck="false"
  />
  {#if value}
    <button
      class="clear"
      aria-label="Clear"
      onclick={() => {
        value = "";
        onInput?.("");
        input?.focus();
      }}><CircleX size={13} /></button
    >
  {/if}
</div>

<style>
  .search {
    display: flex;
    align-items: center;
    gap: 4px;
    background: var(--text-bg);
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 12px;
    padding: 0 6px;
    height: 22px;
    color: var(--secondary-label);
  }
  .search:focus-within {
    outline: 2px solid rgba(10, 132, 255, 0.6);
    outline-offset: -1px;
  }
  input {
    flex: 1;
    min-width: 0;
    background: transparent;
    border: 0;
    outline: none;
    color: var(--label);
    user-select: text;
  }
  input::placeholder {
    color: var(--tertiary-label);
  }
  .clear {
    background: none;
    border: 0;
    padding: 0;
    color: var(--secondary-label);
    display: grid;
    place-items: center;
  }
</style>
