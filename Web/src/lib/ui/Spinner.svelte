<script lang="ts">
  // NSProgressIndicator (spinning style).
  let { size = 16 }: { size?: number } = $props();
</script>

<span class="spinner" style="width:{size}px;height:{size}px" role="progressbar" aria-label="Working"></span>

<style>
  .spinner {
    display: inline-block;
    border: 2px solid rgba(255, 255, 255, 0.2);
    border-top-color: var(--label);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin {
    to { transform: rotate(360deg); }
  }
</style>
