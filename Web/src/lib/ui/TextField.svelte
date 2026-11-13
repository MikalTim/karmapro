<script lang="ts">
  // NSTextField (editable) and NSSecureTextField (`secure`).
  let {
    value = $bindable(""),
    placeholder = "",
    secure = false,
    width,
    disabled = false,
    onChange,
    onEnter,
    monospace = false,
    autofocus = false,
  }: {
    value?: string;
    placeholder?: string;
    secure?: boolean;
    width?: number;
    disabled?: boolean;
    /** Called on every edit (controlTextDidChange). */
    onChange?: (value: string) => void;
    onEnter?: () => void;
    monospace?: boolean;
    autofocus?: boolean;
  } = $props();

  let input: HTMLInputElement | undefined = $state();

  $effect(() => {
    if (autofocus) input?.focus();
  });
</script>

<input
  bind:this={input}
  class="field"
  class:mono={monospace}
  type={secure ? "password" : "text"}
  {placeholder}
  {disabled}
  style={width ? `width:${width}px` : undefined}
  bind:value
  oninput={() => onChange?.(value)}
  onkeydown={(e) => e.key === "Enter" && onEnter?.()}
  spellcheck="false"
  autocomplete="off"
/>
