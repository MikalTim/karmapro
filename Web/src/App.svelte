<script lang="ts">
  // The page is the application: the layers every window shares (windows,
  // alerts, context menus, the folder picker) are mounted here, and the launch
  // sequence of `AppDelegate.applicationDidFinishLaunching` runs: the splash
  // for 3 seconds, then the main window.
  import { api } from "./lib/api";
  import Splash from "./lib/app/Splash.svelte";
  import AlertHost from "./lib/ui/AlertHost.svelte";
  import ContextMenuHost from "./lib/ui/ContextMenuHost.svelte";
  import DirectoryPicker from "./lib/ui/DirectoryPicker.svelte";
  import WindowHost from "./lib/ui/WindowHost.svelte";

  const SPLASH_SECONDS = 3;

  interface AppInfo {
    version: string;
  }

  let version = $state<string | null>(null);
  let splashVisible = $state(true);
  let launched = $state(false);

  $effect(() => {
    api<AppInfo>("GET", "/api/app/info").then((info) => (version = info.version));
    // Esc hides the splash early (EscClosableWindow), but the launch still happens at 3 s.
    const timer = setTimeout(() => {
      splashVisible = false;
      launched = true;
    }, SPLASH_SECONDS * 1000);
    return () => clearTimeout(timer);
  });

  function keydown(event: KeyboardEvent) {
    if (event.key === "Escape") splashVisible = false;
  }
</script>

<svelte:window onkeydown={keydown} />

<div class="desktop" data-launched={launched}>
  <WindowHost />
</div>

{#if splashVisible}
  <div class="splash-layer"><Splash {version} /></div>
{/if}

<ContextMenuHost />
<DirectoryPicker />
<AlertHost />

<style>
  .desktop {
    position: fixed;
    inset: 0;
    display: flex;
    flex-direction: column;
    background: var(--window-bg);
  }
  .splash-layer {
    position: fixed;
    inset: 0;
    z-index: 100000;
    display: flex;
    align-items: center;
    justify-content: center;
  }
</style>
