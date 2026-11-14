<script lang="ts">
  // `MCPSettingsWindowController`: the MCP service controls. Each change is answered with the
  // new state; `mcp.changed` keeps every open copy in step.
  import { api } from "../../lib/api";
  import { on } from "../../lib/events";
  import { showAlert } from "../../lib/ui/alert.svelte";
  import Checkbox from "../../lib/ui/Checkbox.svelte";
  import { serviceButtonTitle, statsText, statusText, type MCPStateDTO } from "./mcp";

  let { windowId }: { windowId: number } = $props();

  // NSLineBreakMode.byTruncatingMiddle: the head of the URL gives way to an ellipsis and the
  // token-bearing tail stays visible.
  const URL_TAIL_LENGTH = 14;

  const EMPTY_STATE: MCPStateDTO = {
    running: false,
    url: "",
    clientConfig: "",
    port: 0,
    allowAI: false,
    autoStart: false,
    scanCount: 0,
    lastError: "",
    startedAt: null,
  };

  let view = $state<MCPStateDTO>(EMPTY_STATE);
  let failure = $state("");
  const errorMessage = $derived(failure || view.lastError);
  const urlHead = $derived(view.url.slice(0, Math.max(0, view.url.length - URL_TAIL_LENGTH)));
  const urlTail = $derived(view.url.slice(-URL_TAIL_LENGTH));
  const stats = $derived(statsText(view, new Date()));

  $effect(() => {
    const unsubscribe = on<MCPStateDTO>("mcp.changed", (next) => {
      view = next;
    });
    api<MCPStateDTO>("GET", "/api/mcp").then((next) => {
      view = next;
    }, reportFailure);
    return unsubscribe;
  });

  function reportFailure(error: unknown): void {
    failure = error instanceof Error ? error.message : String(error);
  }

  async function perform(request: Promise<MCPStateDTO>): Promise<void> {
    try {
      view = await request;
      failure = "";
    } catch (error) {
      reportFailure(error);
    }
  }

  function copy(text: string): void {
    navigator.clipboard.writeText(text).catch(reportFailure);
  }

  async function rotateToken(): Promise<void> {
    const choice = await showAlert({
      message: "Generate a new token?",
      informative: "The current URL stops working and every client must be updated.",
      buttons: ["New Token", "Cancel"],
      sheetOf: windowId,
    });
    if (choice === 0) await perform(api<MCPStateDTO>("POST", "/api/mcp/rotate-token"));
  }
</script>

<div class="settings">
  <div class="title">MCP Service</div>
  <p class="intro">
    Connects Karma Pro's scanner to an MCP client, which can request a vulnerability scan of a directory and read the
    results as SARIF 2.1.0. The service listens on this Mac only and runs while Karma Pro is open.
  </p>

  <div class="status">
    <span class="dot" class:running={view.running}></span>
    <span class="status-text">{statusText(view)}</span>
  </div>
  <div class="url" title={view.url}>
    <span class="url-head">{urlHead}</span><span class="url-tail">{urlTail}</span>
  </div>

  <div class="buttons">
    <button class="button default" onclick={() => void perform(api<MCPStateDTO>("POST", "/api/mcp/toggle"))}>
      {serviceButtonTitle(view.running)}
    </button>
    <button class="button" onclick={() => copy(view.url)}>Copy URL</button>
    <button class="button" onclick={() => copy(view.clientConfig)}>Copy Client Config</button>
    <button class="button" onclick={() => void rotateToken()}>New Token</button>
  </div>

  <hr />

  <Checkbox
    label="Allow AI scans over MCP (uses the selected provider and may cost money)"
    checked={view.allowAI}
    onChange={(allowAI) => void perform(api<MCPStateDTO>("PUT", "/api/mcp", { allowAI }))}
  />
  <Checkbox
    label="Start the service when Karma Pro launches"
    checked={view.autoStart}
    onChange={(autoStart) => void perform(api<MCPStateDTO>("PUT", "/api/mcp", { autoStart }))}
  />

  <div class="config-title">Client configuration</div>
  <div class="config-hint">
    Paste this into the MCP server settings of your client, then restart it. The token is part of the URL, so treat it
    like a password.
  </div>
  <div class="config">{view.clientConfig}</div>

  <hr />

  <div class="stats">{stats}</div>
  {#if errorMessage}<div class="error">{errorMessage}</div>{/if}
  <div class="footer">
    Scans run one at a time so the AI worker pool (1 for a local server, 3 for a hosted provider) is never doubled.
    Quitting Karma Pro stops the service and cancels running scans.
  </div>
</div>

<style>
  .settings {
    box-sizing: border-box;
    min-height: 100%;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    font-size: 12px;
    color: var(--label);
  }
  .title {
    font-size: 15px;
    font-weight: 600;
  }
  .intro,
  .config-hint,
  .stats,
  .footer,
  .error {
    margin: 0;
    font-size: 11px;
    line-height: 1.4;
  }
  .intro,
  .config-hint,
  .stats {
    color: var(--secondary-label);
  }
  .footer {
    color: var(--tertiary-label);
  }
  .error {
    color: var(--system-red);
  }
  .status {
    display: flex;
    align-items: center;
    gap: 8px;
    font-weight: 500;
  }
  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--tertiary-label);
  }
  .dot.running {
    background: var(--system-green);
  }
  .url {
    display: flex;
    min-width: 0;
    font-family: var(--font-mono);
    font-size: 11px;
    white-space: nowrap;
    user-select: text;
  }
  .url-head {
    flex: 1 1 auto;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .url-tail {
    flex: none;
  }
  .buttons {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }
  .button {
    font: inherit;
    color: var(--label);
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid var(--separator);
    border-radius: 5px;
    padding: 3px 10px;
  }
  .button.default {
    background: var(--accent);
    border-color: transparent;
    color: #fff;
  }
  hr {
    width: 100%;
    margin: 0;
    border: 0;
    border-top: 1px solid var(--separator);
  }
  .config-title {
    font-size: 12px;
    font-weight: 600;
  }
  .config {
    height: 118px;
    box-sizing: border-box;
    overflow: auto;
    padding: 8px;
    background: var(--text-bg);
    border: 1px solid var(--separator);
    font-family: var(--font-mono);
    font-size: 11px;
    white-space: pre-wrap;
    word-break: break-all;
    user-select: text;
  }
</style>
