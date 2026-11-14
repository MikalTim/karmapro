<script lang="ts">
  // The file tree sidebar (`FileTreeViewController`). The server filters the tree
  // (language, pull request pruning, search); this shows its reply as an outline in
  // which every folder starts open, as AppKit expands the tree after loading it.
  import { File, Folder } from "@lucide/svelte";
  import Outline from "../../lib/ui/Outline.svelte";
  import { openablePath, rowLabel, treeNodes, type FileTreeNode } from "./fileTree";
  import { treeState } from "./treeState.svelte";

  let { onOpenFile }: { onOpenFile: (path: string) => void } = $props();

  const nodes = $derived(treeNodes(treeState.tree));
  const rootPath = $derived(treeState.tree?.root?.path ?? null);

  let expanded = $state<Record<string, boolean>>({});
  let selectedId = $state<string | null>(null);
  /** The file that stays selected while a folder or the empty area is clicked. */
  let selectedFile: string | null = null;

  // Opening another folder starts the tree from scratch; a refreshed tree keeps its folds.
  $effect(() => {
    void rootPath;
    expanded = {};
    selectedFile = null;
    selectedId = null;
  });

  /** Folders cannot be selected (`shouldSelectItem`), so a click on one leaves the file selection alone. */
  function select(node: FileTreeNode | null): void {
    const path = node ? openablePath(node.data) : null;
    if (path === null) {
      selectedId = selectedFile;
      return;
    }
    selectedFile = path;
    selectedId = path;
    onOpenFile(path);
  }
</script>

<div class="tree">
  {#if treeState.error}<p class="message">{treeState.error}</p>{/if}
  <Outline nodes={nodes} expandAll bind:expanded bind:selectedId onSelect={select} label={labelRow} />
</div>

{#snippet labelRow(node: FileTreeNode)}
  {@const row = rowLabel(node.data)}
  <span class="icon">{#if node.data.isDirectory}<Folder size={14} />{:else}<File size={14} />{/if}</span>
  <span class="name" class:added={row.tone === "added"} class:modified={row.tone === "modified"}>{row.text}</span>
{/snippet}

<style>
  .tree {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    background: var(--control-bg);
    font-size: 13px;
    overflow: hidden;
  }
  .message {
    margin: 0;
    padding: 6px 10px;
    color: var(--system-red);
    white-space: pre-wrap;
  }
  .icon {
    display: grid;
    place-items: center;
    width: 16px;
    color: var(--secondary-label);
    flex: none;
  }
  .name {
    color: var(--label);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    min-width: 0;
  }
  .name.added {
    color: var(--system-green);
  }
  .name.modified {
    color: var(--system-orange);
  }
  .tree :global(.outline) {
    flex: 1;
    min-height: 0;
  }
</style>
