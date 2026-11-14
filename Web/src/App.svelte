<script lang="ts">
  // The page is the application: the layers every window shares (windows, alerts,
  // context menus, the folder picker) are mounted here, and the launch sequence of
  // `AppDelegate.applicationDidFinishLaunching` runs. The pull request and update
  // services start at once; the splash shows for 3 seconds, then the main window
  // opens and the Open Folder panel follows it straight away.
  import { onMount, tick } from "svelte";
  import { api } from "./lib/api";
  import Splash from "./lib/app/Splash.svelte";
  import AlertHost from "./lib/ui/AlertHost.svelte";
  import ContextMenuHost from "./lib/ui/ContextMenuHost.svelte";
  import DirectoryPicker from "./lib/ui/DirectoryPicker.svelte";
  import WindowHost from "./lib/ui/WindowHost.svelte";
  import { startUpdateNotifications } from "./features/app";
  import { startPRNotifications } from "./features/pr";
  import { MainWindow } from "./features/main";
  import { promptForDirectory } from "./features/main/navigation";

  const SPLASH_SECONDS = 3;

  interface AppInfo {
    version: string;
  }

  let version = $state<string | null>(null);
  let splashVisible = $state(true);
  let launched = $state(false);

  // Once per page: both services are idempotent, and neither waits for the splash.
  onMount(() => {
    startPRNotifications();
    startUpdateNotifications();
  });

  $effect(() => {
    api<AppInfo>("GET", "/api/app/info").then((info) => (version = info.version));
    // Esc hides the splash early (EscClosableWindow), but the launch still happens at 3 s.
    const timer = setTimeout(() => void launch(), SPLASH_SECONDS * 1000);
    return () => clearTimeout(timer);
  });

  async function launch(): Promise<void> {
    splashVisible = false;
    launched = true;
    // The main window is created on the next tick, and it installs the actions the
    // Open Folder panel is built on; only then does the panel open.
    await tick();
    await promptForDirectory();
  }

  function keydown(event: KeyboardEvent) {
    if (event.key === "Escape") splashVisible = false;
  }
</script>

<svelte:window onkeydown={keydown} />

<div class="desktop" data-launched={launched}>
  {#if launched}<MainWindow />{/if}
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
