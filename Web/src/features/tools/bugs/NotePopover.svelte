<script lang="ts">
  // The note popover (NotePopoverController): a note on one line of a source
  // file, opened from the gutter. It loads the line's note, saves it (blank
  // text removes it), removes it, and closes after either.
  import { onMount, tick } from "svelte";
  import { api, withQuery } from "../../../lib/api";
  import Popover from "../../../lib/ui/Popover.svelte";
  import TextArea from "../../../lib/ui/TextArea.svelte";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import { messageOf } from "./bugModel";
  import {
    anchorRect,
    fileNameOf,
    noteHeading,
    noteSaveAction,
    removeIsOffered,
    type NoteAnchor,
    type NoteTextDTO,
  } from "./notePopoverModel";

  let {
    path,
    line,
    anchor,
    onClose,
  }: { path: string; line: number; anchor: NoteAnchor; onClose: () => void } = $props();

  let text = $state("");
  let removable = $state(false);
  let loaded = $state(false);
  let area: HTMLDivElement | undefined = $state();

  const noteQuery = $derived(withQuery("/api/notes/line", { path, line }));

  async function load(): Promise<void> {
    try {
      const stored = await api<NoteTextDTO>("GET", noteQuery);
      text = stored.text ?? "";
      removable = removeIsOffered(stored.text);
    } catch (error) {
      await showAlert({ message: messageOf(error), buttons: ["OK"] });
    }
    loaded = true;
    await tick();
    area?.querySelector<HTMLTextAreaElement>("textarea")?.focus();
  }

  async function save(): Promise<void> {
    const action = noteSaveAction(text);
    try {
      if (action.kind === "remove") await api("DELETE", noteQuery);
      else await api("PUT", noteQuery, { text: action.text });
      onClose();
    } catch (error) {
      await showAlert({ message: messageOf(error), buttons: ["OK"] });
    }
  }

  async function remove(): Promise<void> {
    try {
      await api("DELETE", noteQuery);
      onClose();
    } catch (error) {
      await showAlert({ message: messageOf(error), buttons: ["OK"] });
    }
  }

  onMount(() => {
    void load();
  });
</script>

<Popover anchor={anchorRect(anchor)} width={280} height={150} {onClose}>
  <div class="note">
    <div class="heading">{noteHeading(line)}</div>
    <div class="file" title={path}>{fileNameOf(path)}</div>
    <div class="area" bind:this={area}>
      <!-- Shown once the saved note has arrived, so text typed at once is not replaced by it. -->
      {#if loaded}<TextArea bind:value={text} />{/if}
    </div>
    <div class="buttons">
      {#if removable}
        <button class="btn" onclick={() => void remove()}>Remove</button>
      {/if}
      <button class="btn default" disabled={!loaded} onclick={() => void save()}>Save</button>
    </div>
  </div>
</Popover>

<style>
  .note {
    height: 100%;
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    gap: 2px;
    font-family: var(--font-ui);
    color: var(--label);
  }
  .heading {
    font-size: 12px;
    font-weight: 600;
  }
  .file {
    font-size: 10px;
    color: var(--secondary-label);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .area {
    flex: 1;
    min-height: 70px;
    margin-top: 6px;
    display: flex;
  }
  .area :global(textarea) {
    font-size: 12px;
  }
  .buttons {
    margin-top: 8px;
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }
</style>
