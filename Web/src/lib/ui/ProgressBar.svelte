<script lang="ts">
  // NSProgressIndicator (bar). `value` is 0...1; null shows the indeterminate animation.
  let { value = null, width }: { value?: number | null; width?: number } = $props();
</script>

<div class="bar" style={width ? `width:${width}px` : undefined} role="progressbar" aria-valuenow={value === null ? undefined : Math.round(value * 100)}>
  <div class="fill" class:indeterminate={value === null} style={value === null ? undefined : `width:${Math.min(1, Math.max(0, value)) * 100}%`}></div>
</div>

<style>
  .bar {
    height: 6px;
    background: rgba(255, 255, 255, 0.12);
    border-radius: 3px;
    overflow: hidden;
    flex: 1;
  }
  .fill {
    height: 100%;
    background: var(--accent);
    transition: width 0.15s linear;
  }
  .fill.indeterminate {
    width: 30%;
    animation: slide 1.1s ease-in-out infinite;
  }
  @keyframes slide {
    0% { margin-left: -30%; }
    100% { margin-left: 100%; }
  }
</style>
