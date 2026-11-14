<script lang="ts">
  // The AI Assistant window (AIWindowController): prompt templates and their
  // editor, the composer with Send, Continue and New Chat, the response pane,
  // the status line, and the provider, model and key row at the bottom.
  import { onMount } from "svelte";
  import { CircleAlert } from "@lucide/svelte";
  import PopUp from "../../../lib/ui/PopUp.svelte";
  import Spinner from "../../../lib/ui/Spinner.svelte";
  import TextArea from "../../../lib/ui/TextArea.svelte";
  import TextField from "../../../lib/ui/TextField.svelte";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import { chooseFile } from "../../../lib/ui/fileUpload";
  import {
    assistant,
    choosePrompt,
    connect,
    continueChat,
    deletePrompt,
    exportPrompts,
    importPrompts,
    newChat,
    refreshModels,
    refreshModelsOnFirstOpen,
    reportError,
    saveServerURL,
    selectModel,
    selectProvider,
    sendPrompt,
  } from "./assistantStore.svelte";
  import { continueEnabled, liveHTML, newChatEnabled, sendButton, transcriptHTML } from "./chatModel";
  import { openProviderManager } from "./openProviderManager";
  import PromptEditorSheet from "./PromptEditorSheet.svelte";
  import {
    ADD_CUSTOM_PROVIDER,
    effectivePromptID,
    promptPopupItems,
    providerPopupItems,
    removePromptMessage,
    type TextSelection,
  } from "./settingsModel";
  import { statusColor } from "./status";
  import type { AIChatEntry, AIPrompt } from "./types";

  let { windowId }: { windowId: number } = $props();

  const PRIVACY_TITLE = "Privacy & Reliability Notice";
  const PRIVACY_TEXT =
    "When scanning source code with a remote AI model, your source code will be read by a third party, make sure that you do not have any privacy concerns. " +
    "Also note that even though AI models identify in many cases real vulnerabilities, they don't always identify the same issues i.e. if a model reads your code many times it may identify different vulnerabilities, for the same source code, and not necessarily the same as with a previous review.\n\n" +
    "Note, if you want you can use a local model and it may be safer for proprietary source code, so if privacy is a concern use Ollama instead of OpenRouter and point Karma Pro to a local running model.";

  const NO_ENTRIES: AIChatEntry[] = [];
  const NO_PROMPTS: AIPrompt[] = [];

  // Each derived value depends on one part of the state, so a streamed token
  // rebuilds only the live answer, not the whole transcript.
  const transcript = $derived(assistant.chat?.transcript ?? NO_ENTRIES);
  const settledHTML = $derived(transcriptHTML(transcript));
  const liveText = $derived(liveHTML(assistant.chat?.streaming ?? "", assistant.chat?.requestInFlight ?? false));

  const prompts = $derived(assistant.settings?.prompts ?? NO_PROMPTS);
  const promptMenu = $derived(promptPopupItems(prompts));
  const promptValue = $derived(effectivePromptID(prompts, assistant.selectedPromptID) ?? "");
  const selectedPrompt = $derived(prompts.find((prompt) => prompt.id === promptValue) ?? null);
  const providerItems = $derived(providerPopupItems(assistant.settings?.providers ?? []));
  const modelItems = $derived((assistant.settings?.models ?? []).map((model) => ({ title: model, value: model })));
  const send = $derived(sendButton({ requestInFlight: assistant.chat?.requestInFlight ?? false }));

  let root = $state<HTMLDivElement>();
  let scroller = $state<HTMLDivElement>();
  let providerEpoch = $state(0);
  let selection = $state<TextSelection | null>(null);
  let editing = $state<{ existing: AIPrompt | null } | null>(null);
  let pinned = true;

  onMount(() => {
    refreshModelsOnFirstOpen();
  });

  // The response pane follows the stream only while the reader is at the bottom.
  $effect.pre(() => {
    void settledHTML;
    void liveText;
    pinned = scroller === undefined || scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight <= 6;
  });
  $effect(() => {
    void settledHTML;
    void liveText;
    if (scroller && pinned) scroller.scrollTop = scroller.scrollHeight;
  });

  // The caret is remembered when the editor loses focus, because choosing a
  // template from the dropdown takes the focus away first.
  function recordSelection(event: Event): void {
    const target = event.target;
    if (target instanceof HTMLTextAreaElement) {
      selection = { start: target.selectionStart, end: target.selectionEnd };
    }
  }

  function chooseProvider(value: string): void {
    if (value === ADD_CUSTOM_PROVIDER) {
      // AppKit keeps the current provider selected and opens the manager; a
      // remount puts the dropdown back on it.
      providerEpoch += 1;
      openProviderManager();
      return;
    }
    void selectProvider(value);
  }

  function editSelectedPrompt(): void {
    if (selectedPrompt) editing = { existing: selectedPrompt };
  }

  async function removeSelectedPrompt(): Promise<void> {
    const prompt = selectedPrompt;
    if (!prompt) return;
    const choice = await showAlert({
      message: "Remove Prompt",
      informative: removePromptMessage(prompt.title),
      buttons: ["Remove", "Cancel"],
    });
    if (choice !== 0) return;
    try {
      await deletePrompt(prompt.id);
    } catch (error) {
      reportError(error);
    }
  }

  async function importTemplates(): Promise<void> {
    const file = await chooseFile(".json");
    if (file) await importPrompts(file);
  }

  function showPrivacyNotice(): void {
    void showAlert({ message: PRIVACY_TITLE, informative: PRIVACY_TEXT, buttons: ["OK"] });
  }

  // Return sends the prompt, as the Send button is the window's default button,
  // unless it is typed into a control that uses Return itself. The listener is
  // on the window, so it only acts for keys pressed inside this window.
  function keydown(event: KeyboardEvent): void {
    if (event.key !== "Enter" || event.shiftKey || event.defaultPrevented) return;
    const target = event.target;
    if (!(target instanceof Node) || !root?.contains(target)) return;
    if (
      target instanceof HTMLInputElement ||
      target instanceof HTMLTextAreaElement ||
      target instanceof HTMLSelectElement ||
      target instanceof HTMLButtonElement
    ) {
      return;
    }
    event.preventDefault();
    void sendPrompt();
  }
</script>

<svelte:window onkeydown={keydown} />

<div class="assistant" bind:this={root}>
  {#if assistant.settings && assistant.chat}
    <div class="row top">
      <span class="label">Prompt Templates:</span>
      <span class="prompt-menu">
        <PopUp
          items={promptMenu.items}
          value={promptValue}
          disabled={!promptMenu.enabled}
          title="Pick a saved prompt template — its text is pasted into the prompt editor"
          onChange={(value) => choosePrompt(value, selection)}
        />
      </span>
      <button class="btn small" title="Create a new prompt template" onclick={() => (editing = { existing: null })}>
        Add…
      </button>
      <button
        class="btn small"
        title="Edit the selected prompt template"
        disabled={!promptMenu.enabled}
        onclick={editSelectedPrompt}
      >
        Edit…
      </button>
      <button
        class="btn small"
        title="Delete the selected prompt template"
        disabled={!promptMenu.enabled}
        onclick={removeSelectedPrompt}
      >
        Remove
      </button>
      <button class="btn small" title="Save all prompt templates to a JSON file" onclick={exportPrompts}>
        Export…
      </button>
      <button
        class="btn small"
        title="Add prompts from a JSON file (duplicates are skipped)"
        onclick={importTemplates}
      >
        Import…
      </button>
      <button
        class="btn small icon"
        title="About scanning code with a remote AI model"
        aria-label="Privacy notice"
        onclick={showPrivacyNotice}
      >
        <CircleAlert size={14} color="var(--system-red)" />
      </button>
    </div>

    <div class="composer">
      <div class="prompt" onfocusout={recordSelection} onkeyup={recordSelection} onmouseup={recordSelection} role="presentation">
        <TextArea bind:value={assistant.draft} />
      </div>
      <div class="composer-bottom">
        <button
          class="btn"
          title="Clear the conversation and start a new one"
          disabled={!newChatEnabled(assistant.chat)}
          onclick={newChat}
        >
          New Chat
        </button>
        <button
          class="btn"
          title="Resume the interrupted response — the model keeps the full conversation and continues where it stopped"
          disabled={!continueEnabled(assistant.chat)}
          onclick={continueChat}
        >
          Continue
        </button>
        {#if assistant.chat.requestInFlight}
          <span class="spinner" title="Waiting for the model's response…"><Spinner size={14} /></span>
        {/if}
        <button class="send" title={send.tooltip} onclick={sendPrompt}>{send.title}</button>
      </div>
    </div>

    <div class="response">
      <div class="terminal" bind:this={scroller}>{@html settledHTML}{@html liveText}</div>
      {#if assistant.chat.thinking}
        <div class="thinking">
          <Spinner size={12} />
          <span>Thinking…</span>
        </div>
      {/if}
    </div>

    <div class="status" style:color={statusColor(assistant.statusLine.level)}>{assistant.statusLine.text}</div>

    <div class="row bottom">
      <span class="label secondary">Model:</span>
      <span class="model" title="The model used for requests; your choice is remembered">
        <PopUp items={modelItems} value={assistant.settings.selectedModel} onChange={(value) => void selectModel(value)} />
      </span>
      <button class="btn small" title="Re-fetch the model list from the endpoint" onclick={() => refreshModels(true)}>
        Refresh
      </button>
      <span class="provider">
        {#key providerEpoch}
          <PopUp
            items={providerItems}
            value={assistant.settings.selectedProviderID}
            title="Which AI service to use: the shipped OpenRouter and Ollama, or an endpoint you added"
            onChange={chooseProvider}
          />
        {/key}
      </span>
      {#if assistant.settings.requiresAPIKey}
        <span class="label secondary">API Key:</span>
        <TextField secure bind:value={assistant.apiKeyDraft} placeholder="sk-or-…" width={140} />
      {/if}
      {#if assistant.settings.isOllama}
        <span class="label secondary">Connect:</span>
        <span title="Ollama server URL, e.g. http://localhost:11434/v1 — edits are remembered">
          <TextField
            bind:value={assistant.serverDraft}
            placeholder={assistant.settings.serverPlaceholder}
            width={210}
            onEnter={() => saveServerURL(assistant.serverDraft.trim(), true)}
          />
        </span>
      {/if}
      <button
        class="btn small"
        title="Verify the connection (and, for OpenRouter, the key) and refresh the model list"
        onclick={connect}
      >
        Connect
      </button>
    </div>
  {:else}
    <div class="loading"><Spinner size={16} /></div>
    <div class="status" style:color={statusColor(assistant.statusLine.level)}>{assistant.statusLine.text}</div>
  {/if}
</div>

{#if editing}
  <PromptEditorSheet {windowId} existing={editing.existing} onClose={() => (editing = null)} />
{/if}

<style>
  .assistant {
    position: relative;
    display: flex;
    flex-direction: column;
    height: 100%;
    padding: 14px 0;
    background: var(--window-bg);
    color: var(--label);
    font-family: var(--font-ui);
    font-size: 13px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 0 20px;
  }
  .label {
    font-size: 12px;
    white-space: nowrap;
  }
  .secondary {
    color: var(--secondary-label);
  }
  .prompt-menu :global(.popup) {
    max-width: 300px;
  }
  .model :global(.popup) {
    max-width: 200px;
  }
  .provider {
    margin-left: 8px;
  }
  .btn.small.icon {
    padding: 1px 6px;
  }

  .composer {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin: 10px 20px 0;
    padding: 12px 14px;
    border: 1px solid var(--separator);
    border-radius: 16px;
    background: var(--control-bg);
  }
  .prompt {
    display: flex;
    height: 84px;
  }
  .prompt :global(textarea) {
    background: transparent;
    border: none;
    padding: 0;
    font-size: 13px;
    outline: none;
  }
  .composer-bottom {
    display: flex;
    justify-content: flex-end;
    align-items: center;
    gap: 8px;
  }
  .spinner {
    display: inline-flex;
    margin: 0 2px;
  }
  .send {
    min-height: 24px;
    padding: 3px 14px;
    border: 1px solid rgba(0, 0, 0, 0.35);
    border-radius: 5px;
    background: #d97857;
    color: #fff;
    font-size: 13px;
    font-weight: 600;
    cursor: default;
  }

  .response {
    position: relative;
    flex: 1;
    min-height: 0;
    margin: 10px 20px 0;
  }
  .terminal {
    height: 100%;
    overflow: auto;
    padding: 6px 9px;
    border: 1px solid var(--separator);
    border-radius: 10px;
    background: #121417;
    color: #ccdbc4;
    font-family: var(--font-mono);
    font-size: 12px;
    line-height: 1.25;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    user-select: text;
  }
  .terminal :global(.md-bold) {
    font-weight: 700;
  }
  .terminal :global(.md-italic) {
    font-style: italic;
  }
  .terminal :global(.md-code-inline) {
    color: #73d98c;
    background: #212624;
  }
  .terminal :global(.md-code-block) {
    color: #ebebeb;
    background: #212624;
  }
  .terminal :global(.ai-turn),
  .terminal :global(.ai-tool-output) {
    font-size: 11px;
    color: #737a73;
  }
  .terminal :global(.ai-tool) {
    font-size: 11px;
    color: #73d98c;
  }
  .terminal :global(.ai-cursor) {
    font-size: 11px;
    color: #73d98c;
  }
  .thinking {
    position: absolute;
    right: 14px;
    bottom: 10px;
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    color: #737a73;
  }

  .status {
    margin: 8px 20px;
    overflow: hidden;
    font-size: 11px;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .loading {
    display: flex;
    flex: 1;
    align-items: center;
    justify-content: center;
  }
</style>
