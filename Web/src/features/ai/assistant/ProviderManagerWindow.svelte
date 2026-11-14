<script lang="ts">
  // The AI Providers window (ProviderManagerController): the presets and the
  // user's endpoints, with add, edit, remove and test.
  import type { Column } from "../../../lib/ui/Table.svelte";
  import Table from "../../../lib/ui/Table.svelte";
  import Spinner from "../../../lib/ui/Spinner.svelte";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import { closeWindow } from "../../../lib/ui/windows.svelte";
  import { assistant, deleteProvider, testProvider } from "./assistantStore.svelte";
  import ProviderEditorSheet from "./ProviderEditorSheet.svelte";
  import {
    providerButtons,
    providerRows,
    removeProviderMessage,
    selectedProvider,
    type ProviderRow,
  } from "./settingsModel";
  import { statusColor, type StatusLine } from "./status";
  import type { AIProvider, AISettings } from "./types";

  let { windowId }: { windowId: number } = $props();

  const NO_PROVIDERS: AIProvider[] = [];

  let root = $state<HTMLDivElement>();
  let selectedID = $state<string | null>(null);
  let status = $state<StatusLine>({ text: "", level: "info" });
  let testing = $state(false);
  let editing = $state<{ existing: AIProvider | null } | null>(null);

  const providers = $derived(assistant.settings?.providers ?? NO_PROVIDERS);
  const rows = $derived(providerRows(providers));
  const selected = $derived(selectedProvider(providers, selectedID));
  const buttons = $derived(providerButtons(selected));

  const columns: Column<ProviderRow>[] = [
    {
      id: "name",
      title: "Name",
      width: 190,
      value: (row) => row.name,
      style: (row) => (row.builtin ? "color: var(--secondary-label)" : undefined),
    },
    { id: "url", title: "Base URL", width: 300, value: (row) => row.url, style: () => "color: var(--secondary-label)" },
    { id: "key", title: "Key", width: 70, value: (row) => row.key, style: () => "color: var(--secondary-label)" },
  ];

  function edit(): void {
    const provider = selected;
    if (provider && !provider.isBuiltin) editing = { existing: provider };
  }

  async function remove(): Promise<void> {
    const provider = selected;
    if (!provider || provider.isBuiltin) return;
    const choice = await showAlert({
      message: "Remove Provider",
      informative: removeProviderMessage(provider.name),
      buttons: ["Remove", "Cancel"],
    });
    if (choice !== 0) return;
    try {
      const settings = await deleteProvider(provider.id);
      status = { text: settings.status, level: settings.level };
    } catch (error) {
      status = { text: error instanceof Error ? error.message : String(error), level: "error" };
    }
  }

  async function test(): Promise<void> {
    const provider = selected;
    if (!provider) return;
    testing = true;
    status = { text: `Testing ${provider.name}\u2026`, level: "info" };
    try {
      const result = await testProvider(provider.id);
      if (result) status = { text: result.status, level: result.level };
    } catch (error) {
      status = { text: error instanceof Error ? error.message : String(error), level: "error" };
    } finally {
      testing = false;
    }
  }

  function saved(settings: AISettings): void {
    editing = null;
    status = { text: settings.status, level: settings.level };
  }

  // Return closes the window, since Done is the window's default button. The
  // listener is on the window, so only keys pressed inside this window count.
  function keydown(event: KeyboardEvent): void {
    if (event.key !== "Enter" || editing !== null || event.defaultPrevented) return;
    const target = event.target;
    if (!(target instanceof Node) || !root?.contains(target)) return;
    if (target instanceof HTMLButtonElement || target instanceof HTMLInputElement) return;
    event.preventDefault();
    void closeWindow(windowId);
  }
</script>

<svelte:window onkeydown={keydown} />

<div class="manager" bind:this={root}>
  <p class="header">
    Karma Pro ships with OpenRouter and Ollama. Add any OpenAI-compatible endpoint , including a local server such as
    LM Studio, vLLM or llama.cpp.
  </p>

  <div class="grid-wrap">
    <Table {columns} {rows} rowKey={(row) => row.id} bind:selectedKey={selectedID} onDoubleClick={edit} />
  </div>

  <div class="buttons">
    <button class="btn" title="Add an OpenAI-compatible endpoint" onclick={() => (editing = { existing: null })}>
      Add…
    </button>
    <button class="btn" title="Edit the selected endpoint's name, URL or key" disabled={!buttons.edit} onclick={edit}>
      Edit…
    </button>
    <button
      class="btn"
      title="Remove the selected endpoint and its saved key"
      disabled={!buttons.remove}
      onclick={remove}
    >
      Remove
    </button>
    <button
      class="btn"
      title="Check the endpoint answers and the model can be used"
      disabled={!buttons.test}
      onclick={test}
    >
      Test
    </button>
    {#if testing}
      <Spinner size={14} />
    {/if}
    <span class="spacer"></span>
    <button class="btn default" title="Close this window" onclick={() => closeWindow(windowId)}>Done</button>
  </div>

  <div class="status" style:color={statusColor(status.level)}>{status.text}</div>
</div>

{#if editing}
  <ProviderEditorSheet {windowId} existing={editing.existing} onClose={() => (editing = null)} onSaved={saved} />
{/if}

<style>
  .manager {
    display: flex;
    flex-direction: column;
    gap: 12px;
    height: 100%;
    padding: 16px 20px;
    background: var(--window-bg);
    color: var(--label);
    font-family: var(--font-ui);
    font-size: 13px;
  }
  .header {
    margin: 0;
    font-size: 12px;
    color: var(--secondary-label);
  }
  .grid-wrap {
    display: flex;
    flex: 1;
    min-height: 0;
  }
  .buttons {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .spacer {
    flex: 1;
  }
  .status {
    font-size: 11px;
    overflow-wrap: anywhere;
  }
</style>
