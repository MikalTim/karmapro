<script lang="ts">
  // NSSlider with the value label next to it.
  let {
    value = $bindable(0),
    min = 0,
    max = 1,
    step = 0.01,
    width = 160,
    format = (v: number) => String(v),
    onChange,
  }: {
    value?: number;
    min?: number;
    max?: number;
    step?: number;
    width?: number;
    /** Label text for the current value (the Swift label's string format). */
    format?: (value: number) => string;
    onChange?: (value: number) => void;
  } = $props();
</script>

<span class="slider">
  <input type="range" {min} {max} {step} bind:value style="width:{width}px" oninput={() => onChange?.(value)} />
  <span class="value secondary">{format(value)}</span>
</span>

<style>
  .slider {
    display: inline-flex;
    align-items: center;
    gap: 8px;
  }
  input {
    accent-color: var(--accent);
  }
  .value {
    min-width: 36px;
  }
</style>
