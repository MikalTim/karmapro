<script lang="ts">
  // `SplashWindowController` / `SplashView`: the bundled picture covering a
  // 480 x 320 panel, a top scrim under the "Karma Pro" wordmark, and credit and
  // version labels in the bottom corners. Without the picture it falls back to a
  // plain dark panel with a larger wordmark and no labels.
  import { apiBlob } from "../api";

  let { version }: { version: string | null } = $props();

  let imageUrl = $state<string | null>(null);
  let failed = $state(false);

  $effect(() => {
    let url: string | null = null;
    let cancelled = false;
    apiBlob("/api/resources/SplashImage.jpg").then(
      (blob) => {
        if (cancelled) return;
        url = URL.createObjectURL(blob);
        imageUrl = url;
      },
      () => {
        if (!cancelled) failed = true;
      },
    );
    return () => {
      cancelled = true;
      if (url) URL.revokeObjectURL(url);
    };
  });
</script>

<div class="splash" role="img" aria-label="Karma Pro">
  {#if imageUrl}
    <img src={imageUrl} alt="" draggable="false" />
    <div class="scrim"></div>
    <div class="title">Karma Pro</div>
    <div class="pill credit">
      <div>https://reviewcode.org</div>
      <div>brought to you by cipher.org.uk</div>
    </div>
    {#if version}<div class="pill version">Version {version}</div>{/if}
  {:else if failed}
    <div class="title plain">Karma Pro</div>
  {/if}
</div>

<style>
  .splash {
    position: relative;
    width: 480px;
    height: 320px;
    background: rgb(10, 15, 28);
    overflow: hidden;
    box-shadow: var(--shadow);
    user-select: none;
  }
  img {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .scrim {
    position: absolute;
    left: 0;
    right: 0;
    top: 0;
    height: 30%;
    background: linear-gradient(to bottom, rgba(0, 0, 0, 0.55), rgba(0, 0, 0, 0));
  }
  .title {
    position: absolute;
    left: 0;
    right: 0;
    top: 14px;
    text-align: center;
    font-size: 38px;
    font-weight: 800;
    line-height: 1.2;
    color: #fff;
    text-shadow: 0 1px 8px rgba(0, 0, 0, 0.75);
  }
  .title.plain {
    font-size: 44px;
    text-shadow: none;
  }
  .pill {
    position: absolute;
    bottom: 5px;
    padding: 3px 5px;
    border-radius: 4px;
    background: rgba(0, 0, 0, 0.55);
    color: rgba(255, 255, 255, 0.7);
    font-size: 10px;
    line-height: 12px;
  }
  .credit {
    left: 5px;
  }
  .credit div + div {
    margin-top: 2px;
  }
  .version {
    right: 5px;
  }
</style>
