<script lang="ts">
  // An editable multi-line NSTextView with plain text.
  let {
    value = $bindable(""),
    placeholder = "",
    readonly = false,
    monospace = false,
    onChange,
    rows,
  }: {
    value?: string;
    placeholder?: string;
    readonly?: boolean;
    monospace?: boolean;
    onChange?: (value: string) => void;
    rows?: number;
  } = $props();
</script>

<textarea
  class="field area"
  class:mono={monospace}
  {placeholder}
  {readonly}
  {rows}
  bind:value
  oninput={() => onChange?.(value)}
  spellcheck="false"
></textarea>

<style>
  .area {
    flex: 1;
    min-height: 0;
    resize: none;
    padding: 6px 8px;
    line-height: 1.35;
    white-space: pre-wrap;
  }
</style>
