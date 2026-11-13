<script lang="ts">
  import { Folder, File as FileIcon } from "@lucide/svelte";
  import { api, withQuery } from "../api";
  import Checkbox from "./Checkbox.svelte";
  import { finishPicker, lastPickedPath, pickerState } from "./directoryPicker.svelte";

  interface Entry {
    name: string;
    path: string;
    isDirectory: boolean;
  }
  interface Listing {
    path: string;
    parent?: string;
    entries: Entry[];
  }

  const pending = $derived(pickerState.pending);
  let listing = $state<Listing | null>(null);
  let typed = $state("");
  let selected = $state<string | null>(null);
  let showHidden = $state(false);
  let error = $state("");
  let shownFor: object | null = null;

  async function load(path: string | undefined) {
    if (!pending) return;
    error = "";
    try {
      listing = await api<Listing>(
        "GET",
        withQuery("/api/fs/list", { path, files: pending.options.files ? 1 : 0, hidden: showHidden ? 1 : 0 }),
      );
      typed = listing.path;
      selected = null;
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    }
  }

  $effect(() => {
    if (pending && pending !== shownFor) {
      shownFor = pending;
      showHidden = false;
      void load(pending.options.startPath ?? lastPickedPath() ?? undefined);
    }
  });

  const chosen = $derived(selected ?? (pending?.options.files ? null : listing?.path ?? null));

  function open(entry: Entry) {
    if (entry.isDirectory) void load(entry.path);
    else finishPicker(entry.path);
  }

  function keydown(event: KeyboardEvent) {
    if (!pending) return;
    if (event.key === "Escape") {
      event.stopPropagation();
      finishPicker(null);
    }
  }
</script>

<svelte:window onkeydowncapture={keydown} />

{#if pending}
  <div class="scrim">
    <div class="panel" role="dialog" aria-modal="true" aria-label="Choose">
      <div class="message">{pending.options.message ?? (pending.options.files ? "Choose a file." : "Choose a folder.")}</div>
      <div class="path-row">
        <button class="btn small" disabled={!listing?.parent} onclick={() => load(listing?.parent)}>Up</button>
        <input
          class="field path"
          bind:value={typed}
          onkeydown={(e) => e.key === "Enter" && load(typed)}
          spellcheck="false"
          aria-label="Path"
        />
      </div>
      <div class="list selectable" role="listbox">
        {#if listing}
          {#each listing.entries as entry (entry.path)}
            <div
              class="entry"
              class:selected={selected === entry.path}
              role="option"
              aria-selected={selected === entry.path}
              tabindex="-1"
              onclick={() => (selected = entry.isDirectory && !pending.options.files ? entry.path : entry.path)}
              ondblclick={() => open(entry)}
              onkeydown={(e) => e.key === "Enter" && open(entry)}
            >
              {#if entry.isDirectory}<Folder size={14} />{:else}<FileIcon size={14} />{/if}
              <span>{entry.name}</span>
            </div>
          {:else}
            <div class="secondary pad">This folder is empty.</div>
          {/each}
        {/if}
      </div>
      {#if error}<div class="error">{error}</div>{/if}
      <div class="footer">
        <Checkbox bind:checked={showHidden} label="Show hidden files" onChange={() => load(listing?.path)} />
        <span class="grow"></span>
        <button class="btn" onclick={() => finishPicker(null)}>Cancel</button>
        <button class="btn default" disabled={!chosen} onclick={() => chosen && finishPicker(chosen)}>
          {pending.options.prompt ?? "Open"}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .scrim {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.35);
    display: flex;
    justify-content: center;
    align-items: flex-start;
    z-index: 100500;
  }
  .panel {
    margin-top: 8vh;
    width: 520px;
    max-width: calc(100vw - 24px);
    height: 460px;
    max-height: 80vh;
    background: #323234;
    border-radius: 10px;
    box-shadow: var(--shadow);
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .message {
    font-weight: 600;
  }
  .path-row {
    display: flex;
    gap: 8px;
  }
  .path {
    flex: 1;
  }
  .list {
    flex: 1;
    min-height: 0;
    overflow: auto;
    background: var(--control-bg);
    border: 1px solid rgba(255, 255, 255, 0.1);
  }
  .entry {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 2px 8px;
    height: 22px;
    white-space: nowrap;
  }
  .entry.selected {
    background: var(--accent);
    color: #fff;
  }
  .pad {
    padding: 8px;
  }
  .error {
    color: var(--system-red);
    font-size: 11px;
  }
  .footer {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .grow {
    flex: 1;
  }
</style>
