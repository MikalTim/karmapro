<script lang="ts">
  // The wiki's page list (WikiWindowController): a search field, the page
  // table, and the New Page, Open, Rename, Delete, Backup and Import buttons.
  // The list follows `wiki.changed`.
  import { onMount } from "svelte";
  import { api, withQuery } from "../../../../lib/api";
  import { on } from "../../../../lib/events";
  import Table, { type Column } from "../../../../lib/ui/Table.svelte";
  import SearchField from "../../../../lib/ui/SearchField.svelte";
  import { showAlert } from "../../../../lib/ui/alert.svelte";
  import { openWikiEditorWindow } from "../editor";
  import { backupWiki, deleteWiki, importWiki, newWikiPage, renameWiki } from "./wikiActions";
  import { messageOf, selectionAfterReload, wikiCellValue, type WikiListDTO, type WikiPageDTO } from "./wikiListModel";

  // Windows receive their id; the list does not need it itself.
  let { windowId }: { windowId: number } = $props();

  const columns: Column<WikiPageDTO>[] = [
    { id: "title", title: "Page", width: 340 },
    { id: "created", title: "Created", width: 140 },
    { id: "updated", title: "Updated", width: 140 },
  ];

  let pages = $state<WikiPageDTO[]>([]);
  let statusText = $state("");
  let query = $state("");
  let selectedKey = $state<string | null>(null);
  let requestSeq = 0;

  const selected = $derived(pages.find((page) => page.slug === selectedKey) ?? null);

  async function reload(): Promise<void> {
    // Answers to older searches are dropped, so the list always shows the latest query.
    const seq = ++requestSeq;
    try {
      const result = await api<WikiListDTO>("GET", withQuery("/api/wiki", { query }));
      if (seq !== requestSeq) return;
      pages = result.pages;
      statusText = result.statusText;
      selectedKey = selectionAfterReload(result.pages, selectedKey);
    } catch (error) {
      if (seq === requestSeq) await showAlert({ message: messageOf(error), buttons: ["OK"] });
    }
  }

  // Runs one action, shows its failure if it throws, then refreshes the list.
  async function run(action: () => Promise<void>): Promise<void> {
    try {
      await action();
    } catch (error) {
      await showAlert({ message: messageOf(error), buttons: ["OK"] });
    }
    await reload();
  }

  function openSelected(): void {
    if (selected) void openWikiEditorWindow({ slug: selected.slug });
  }

  async function renameSelected(): Promise<void> {
    if (selected) await run(() => renameWiki(selected));
  }

  async function deleteSelected(): Promise<void> {
    if (selected) await run(() => deleteWiki(selected));
  }

  async function newPage(): Promise<void> {
    await run(async () => {
      const page = await newWikiPage();
      void openWikiEditorWindow({ slug: page.slug });
    });
  }

  onMount(() => {
    void reload();
    return on("wiki.changed", () => void reload());
  });
</script>

<div class="wiki">
  <div class="top">
    <SearchField
      placeholder="Search pages (title or body)"
      width={260}
      onInput={(value) => {
        query = value;
        void reload();
      }}
    />
    <div class="buttons">
      <button class="btn" onclick={() => void newPage()}>New Page</button>
      <button class="btn" onclick={openSelected}>Open</button>
      <button class="btn" onclick={() => void renameSelected()}>Rename…</button>
      <button class="btn" onclick={() => void deleteSelected()}>Delete…</button>
      <button class="btn" onclick={() => void run(backupWiki)}>Backup…</button>
      <button class="btn" onclick={() => void run(importWiki)}>Import…</button>
    </div>
  </div>
  <span class="status">{statusText}</span>

  <div class="grid">
    <Table
      {columns}
      rows={pages}
      rowKey={(page) => page.slug}
      bind:selectedKey
      onDoubleClick={(page) => void openWikiEditorWindow({ slug: page.slug })}
    >
      {#snippet cell(page: WikiPageDTO, column: Column<WikiPageDTO>)}
        <span title={column.id === "title" ? page.slug : undefined}>{wikiCellValue(page, column.id)}</span>
      {/snippet}
    </Table>
  </div>
</div>

<style>
  .wiki {
    height: 100%;
    display: flex;
    flex-direction: column;
    box-sizing: border-box;
    font: 13px var(--font-ui);
    color: var(--label);
    background: var(--window-bg);
  }
  .top {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 10px;
    padding: 12px 16px 0;
  }
  .buttons {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 10px;
  }
  .status {
    padding: 4px 16px 0;
    font-size: 12px;
    color: var(--secondary-label);
  }
  .grid {
    flex: 1 1 auto;
    min-height: 120px;
    margin-top: 4px;
    display: flex;
    flex-direction: column;
  }
</style>
