<script lang="ts">
  // NSPopUpButton: a menu button whose title is the selected item. Items
  // with `separator: true` render as a rule and cannot be chosen.
  export interface PopUpItem {
    title: string;
    value?: string;
    separator?: boolean;
    disabled?: boolean;
  }

  let {
    items,
    value = $bindable(""),
    width,
    onChange,
    disabled = false,
    title,
  }: {
    items: PopUpItem[];
    value?: string;
    width?: number;
    onChange?: (value: string) => void;
    disabled?: boolean;
    title?: string;
  } = $props();

  function change(event: Event) {
    value = (event.currentTarget as HTMLSelectElement).value;
    onChange?.(value);
  }
</script>

<select class="popup" {disabled} {title} style={width ? `width:${width}px` : undefined} {value} onchange={change}>
  {#each items as item, i (i)}
    {#if item.separator}
      <hr />
    {:else}
      <option value={item.value ?? item.title} disabled={item.disabled} selected={(item.value ?? item.title) === value}>{item.title}</option>
    {/if}
  {/each}
</select>

<style>
  .popup {
    appearance: none;
    background: var(--bezel) url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='10' height='14'><path d='M2 5l3-3 3 3M2 9l3 3 3-3' fill='none' stroke='white' stroke-width='1.4'/></svg>") no-repeat right 6px center;
    border: 1px solid var(--bezel-border);
    border-radius: 5px;
    padding: 2px 22px 2px 8px;
    min-height: 22px;
    color: var(--label);
    cursor: default;
  }
  .popup:disabled {
    color: var(--tertiary-label);
  }
  .popup:focus-visible {
    outline: 2px solid rgba(10, 132, 255, 0.6);
    outline-offset: 1px;
  }
  option {
    background: #3a3a3c;
    color: #fff;
  }
</style>
