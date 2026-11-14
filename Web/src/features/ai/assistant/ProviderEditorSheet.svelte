<script lang="ts">
  // The add and edit form for one endpoint (ProviderEditorController), shown as a
  // sheet of the AI Providers window. The server checks the fields and saves
  // nothing when one is invalid; the refusal comes back as the alert's text.
  import { onMount, untrack } from "svelte";
  import Checkbox from "../../../lib/ui/Checkbox.svelte";
  import Sheet from "../../../lib/ui/Sheet.svelte";
  import TextField from "../../../lib/ui/TextField.svelte";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import { loadProviderKey, saveProvider } from "./assistantStore.svelte";
  import type { AIProvider, AISettings } from "./types";

  let {
    windowId,
    existing,
    onClose,
    onSaved,
  }: {
    windowId: number;
    existing: AIProvider | null;
    onClose: () => void;
    onSaved: (settings: AISettings) => void;
  } = $props();

  // The form starts from the endpoint being edited; the values then belong to the form, so later changes to the
  // list do not reset it.
  let name = $state(untrack(() => existing?.name ?? ""));
  let baseURL = $state(untrack(() => existing?.baseURL ?? ""));
  let requiresKey = $state(untrack(() => existing?.requiresAPIKey ?? true));
  let apiKey = $state("");
  // An edited endpoint's saved key arrives from the server; until then the key field and Save wait, so a key typed
  // at once is not replaced by it.
  let keyLoaded = $state(untrack(() => existing === null));
  const heading = $derived(existing ? "Edit Provider" : "Add Provider");

  onMount(() => {
    if (existing === null) return;
    loadProviderKey(existing.id)
      .then((key) => (apiKey = key))
      .catch((error: unknown) => {
        void showAlert({
          message: "Cannot Load the API Key",
          informative: error instanceof Error ? error.message : String(error),
          style: "warning",
          buttons: ["OK"],
        });
      })
      .finally(() => (keyLoaded = true));
  });

  async function save(): Promise<void> {
    try {
      const settings = await saveProvider(existing, { name, baseURL, requiresAPIKey: requiresKey, apiKey });
      onSaved(settings);
    } catch (error) {
      await showAlert({
        message: "Cannot Save Provider",
        informative: error instanceof Error ? error.message : String(error),
        style: "warning",
        buttons: ["OK"],
      });
    }
  }
</script>

<Sheet {windowId} width={460}>
  <div class="sheet">
    <div class="heading">{heading}</div>
    <div class="grid">
      <span class="label">Name:</span>
      <TextField bind:value={name} placeholder="My Provider" autofocus onEnter={save} />

      <span class="label">Base URL:</span>
      <TextField bind:value={baseURL} placeholder="https://api.example.com/v1" onEnter={save} />

      <span></span>
      <div class="hint">
        The OpenAI-compatible root, e.g. https://api.example.com/v1 — a trailing /chat/completions is stripped
        automatically.
      </div>

      <span></span>
      <div><Checkbox bind:checked={requiresKey} label="This endpoint requires an API key" /></div>

      <span class="label" class:disabled={!requiresKey || !keyLoaded}>API Key:</span>
      <TextField secure bind:value={apiKey} placeholder="sk-…" disabled={!requiresKey || !keyLoaded} />
    </div>
    <div class="buttons">
      <button class="btn" onclick={onClose}>Cancel</button>
      <button class="btn default" disabled={!keyLoaded} onclick={save}>{existing ? "Save" : "Add"}</button>
    </div>
  </div>
</Sheet>

<style>
  .sheet {
    display: flex;
    flex-direction: column;
    gap: 12px;
    font-family: var(--font-ui);
    font-size: 12px;
    color: var(--label);
  }
  .heading {
    font-size: 13px;
    font-weight: 700;
  }
  .grid {
    display: grid;
    grid-template-columns: 80px 1fr;
    align-items: center;
    gap: 10px 8px;
  }
  .grid :global(.field) {
    width: 100%;
    font-size: 12px;
  }
  .label {
    text-align: right;
    color: var(--secondary-label);
  }
  .label.disabled {
    color: var(--tertiary-label);
  }
  .hint {
    font-size: 11px;
    color: var(--secondary-label);
  }
  .buttons {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }
</style>
