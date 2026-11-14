<script lang="ts">
  // `HelpWindowController`: the help page from `GET /api/help`, shown in a sandboxed frame
  // like the WebKit view. The splash picture needs the API headers, which an <img> cannot
  // send, so it is fetched here and the page carries it as a data URL.
  import { apiBlob, apiText } from "../../lib/api";
  import { HELP_SPLASH_SRC, dataUrl, withSplashSource } from "./help";

  // The window host always passes `windowId`; this window has no use for it.
  let { windowId }: { windowId: number } = $props();

  let srcdoc = $state<string | null>(null);
  let failure = $state<string | null>(null);

  $effect(() => {
    let cancelled = false;
    apiText("GET", "/api/help")
      .then(async (page) => {
        // A missing picture leaves the page text in place, as the Mac window does.
        const blob = await apiBlob(HELP_SPLASH_SRC).catch(() => null);
        const picture = blob ? await dataUrl(blob).catch(() => null) : null;
        if (!cancelled) srcdoc = picture ? withSplashSource(page, picture) : page;
      })
      .catch((error: unknown) => {
        if (!cancelled) failure = error instanceof Error ? error.message : String(error);
      });
    return () => {
      cancelled = true;
    };
  });
</script>

<div class="help">
  {#if srcdoc !== null}
    <iframe class="page" title="Karma Pro Help & User Guide" {srcdoc} sandbox=""></iframe>
  {:else if failure !== null}
    <p class="failure">{failure}</p>
  {/if}
</div>

<style>
  .help {
    width: 100%;
    height: 100%;
  }
  .page {
    display: block;
    width: 100%;
    height: 100%;
    border: 0;
  }
  .failure {
    padding: 16px;
    color: var(--secondary-label);
  }
</style>
