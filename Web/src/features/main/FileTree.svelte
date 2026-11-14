<script lang="ts">
  // The file tree sidebar (`FileTreeViewController`). The server filters the tree
  // (language, pull request pruning, search); this shows its reply as an outline in
  // which every folder starts open, as AppKit expands the tree after loading it.
  import { File, Folder } from "@lucide/svelte";
  import Outline from "../../lib/ui/Outline.svelte";
  import { nextSelectableFile, openablePath, rowLabel, treeNodes, visibleNodes, type FileTreeNode } from "./fileTree";
  import MiddleText from "./MiddleText.svelte";
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

  // A new language filter expands the whole tree again (`applyLanguageFilter` ends in `reloadAndExpand`).
  $effect(() => {
    void treeState.language;
    expanded = {};
  });

  /** True while the outline handles a key press, which moves the selection but opens nothing. */
  let keyboardMove = false;

  /**
   * Folders cannot be selected (`shouldSelectItem`): a click on one leaves the file selection alone
   * and an arrow key moves on to the next file. Only a click opens a file (`outlineClicked`); the
   * arrow keys just move the selection.
   */
  function select(node: FileTreeNode | null): void {
    let target = node;
    if (node !== null && openablePath(node.data) === null && keyboardMove) {
      target = nextSelectableFile(visibleNodes(nodes, expanded), selectedFile, node);
    }
    const path = target ? openablePath(target.data) : null;
    if (path === null) {
      selectedId = selectedFile;
      return;
    }
    selectedFile = path;
    selectedId = path;
    if (!keyboardMove) onOpenFile(path);
  }

  /** A double click expands a folder and does nothing to an open one (`outlineDoubleClicked`). */
  function doubleClick(event: MouseEvent): void {
    event.stopPropagation();
    if (!(event.target instanceof Element)) return;
    const row = event.target.closest('[role="treeitem"]');
    if (row === null || row.parentElement === null) return;
    const rows = Array.from(row.parentElement.querySelectorAll('[role="treeitem"]'));
    const node = visibleNodes(nodes, expanded)[rows.indexOf(row)];
    if (node?.children && node.children.length > 0) expanded[node.id] = true;
  }
</script>

<!-- The capture handlers wrap the outline's own handlers: they mark key presses and take the double click over. -->
<div
  class="tree"
  role="presentation"
  onkeydowncapture={() => (keyboardMove = true)}
  onkeydown={() => (keyboardMove = false)}
  ondblclickcapture={doubleClick}
>
  {#if treeState.error}<p class="message">{treeState.error}</p>{/if}
  <Outline nodes={nodes} expandAll bind:expanded bind:selectedId onSelect={select} label={labelRow} />
</div>

{#snippet labelRow(node: FileTreeNode)}
  {@const row = rowLabel(node.data)}
  <span class="icon">{#if node.data.isDirectory}<Folder size={14} />{:else}<File size={14} />{/if}</span>
  <span class="name" class:added={row.tone === "added"} class:modified={row.tone === "modified"}>
    <MiddleText text={row.text} />
  </span>
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
    display: flex;
    flex: 1;
    min-width: 0;
    margin: 0 4px 0 4px;
    color: var(--label);
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
  /* The column follows the pane's width and long names are cut in the middle, so a row never grows past the pane. */
  .tree :global(.row) {
    min-width: 0;
  }
</style>
