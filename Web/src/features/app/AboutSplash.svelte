<script lang="ts">
  // The splash panel of About. The Mac panel is borderless, floats above the windows and
  // ignores the pointer (`hitTest` returns nil), so it is drawn over the page rather than as
  // a window of the window system, which would add a title bar.
  import { api } from "../../lib/api";
  import Splash from "../../lib/app/Splash.svelte";

  interface AppInfo {
    version: string;
  }

  let version = $state<string | null>(null);

  $effect(() => {
    let cancelled = false;
    api<AppInfo>("GET", "/api/app/info").then(
      (info) => {
        if (!cancelled) version = info.version;
      },
      () => {
        // Without the version the panel still shows the picture, as the Mac splash does without its label.
      },
    );
    return () => {
      cancelled = true;
    };
  });
</script>

<div class="overlay">
  <Splash {version} />
</div>

<style>
  .overlay {
    position: fixed;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    pointer-events: none;
    z-index: 90000;
  }
</style>
