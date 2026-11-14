<script lang="ts">
  // The entry-point finder (`EntryPointsWindowController`): the project's entries
  // grouped by category on the left, and the flow of the selected entry on the right.
  import { DataFlowDiagram } from "../flow";
  import { showFileInMainWindow } from "../../main/navigation";
  import Checkbox from "../../../lib/ui/Checkbox.svelte";
  import Outline from "../../../lib/ui/Outline.svelte";
  import ProgressBar from "../../../lib/ui/ProgressBar.svelte";
  import {
    ENTRY_FLOW_STYLE,
    ENTRY_POINTS_TITLE,
    badgeColor,
    nodeLocation,
    outlineNodes,
    progressFraction,
    sitesText,
    traceDiagram,
    type EntryTreeNode,
  } from "./entryPointsModel";
  import { entryPoints, setIndirectEntries, traceEntrySite } from "./entryPointsSession.svelte";

  let { windowId }: { windowId: number } = $props();

  const INDIRECT_LABEL = "Include indirect entries (file reads, persisted data, serialization)";

  const snapshot = $derived(entryPoints.state);
  const outline = $derived(snapshot ? outlineNodes(snapshot.groups) : []);
  const diagram = $derived(entryPoints.trace ? traceDiagram(entryPoints.trace) : null);
  const caption = $derived(entryPoints.tracing ?? entryPoints.trace?.caption ?? "");

  // `reload()` expands every category again after each search.
  let expanded = $state<Record<string, boolean>>({});
  $effect(() => {
    void entryPoints.groupsRun;
    expanded = {};
  });

  function openSite(node: EntryTreeNode) {
    const row = node.data;
    if (row.kind === "site") showFileInMainWindow(row.site.path, row.site.line);
  }

  function selectNode(node: EntryTreeNode | null) {
    const row = node?.data;
    if (row?.kind === "site") void traceEntrySite(row.site);
  }

  function openDiagramNode(name: string) {
    if (!entryPoints.trace) return;
    const location = nodeLocation(entryPoints.trace, name);
    if (location) showFileInMainWindow(location.path, location.line);
  }
</script>

<div class="entry-points">
  <div class="header">
    <div class="title">{snapshot?.title ?? ENTRY_POINTS_TITLE}</div>
    <div class="controls">
      <Checkbox
        checked={snapshot?.indirectEnabled ?? false}
        label={INDIRECT_LABEL}
        onChange={(on) => setIndirectEntries(on)}
      />
      <span class="count">{snapshot?.countText ?? ""}</span>
      <span class="spacer"></span>
      {#if snapshot?.busy}
        <div class="progress">
          <ProgressBar value={progressFraction(snapshot.progressDone, snapshot.progressTotal)} width={180} />
          <span class="secondary">{snapshot.progressText}</span>
        </div>
      {/if}
    </div>
  </div>

  <div class="body">
    <div class="list">
      <Outline
        nodes={outline}
        selectedId={entryPoints.selectedSiteID}
        bind:expanded
        expandAll
        rowHeight={20}
        onSelect={selectNode}
        onDoubleClick={openSite}
      >
        {#snippet label(node)}
          {@const row = node.data}
          {#if row.kind === "group"}
            <span class="category text">{row.group.category}</span>
            <span class="secondary text">{` — ${sitesText(row.group.sites.length)}`}</span>
            <span class="badge text" style="color: {badgeColor(row.group.origin)}">{`  ${row.group.badge}`}</span>
          {:else}
            <span class="site-label text">{row.site.label}</span>
            <span class="secondary text">{`  ${row.site.displaySnippet}`}</span>
            <span class="source-kind text">{`  · ${row.site.sourceKind}`}</span>
          {/if}
        {/snippet}
      </Outline>
    </div>

    <div class="flow">
      <div class="caption secondary">{caption}</div>
      <div class="diagram">
        {#if diagram}
          <DataFlowDiagram graph={diagram} flowStyle={ENTRY_FLOW_STYLE} onNodeClick={openDiagramNode} />
        {/if}
      </div>
    </div>
  </div>
</div>

<style>
  .entry-points {
    display: flex;
    flex-direction: column;
    height: 100%;
    box-sizing: border-box;
    padding: 14px 16px 16px;
    background: var(--window-bg);
    color: var(--label);
    font: 13px var(--font-ui);
  }
  .header {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .title {
    font-size: 16px;
    font-weight: 600;
  }
  .controls {
    display: flex;
    align-items: center;
    gap: 12px;
    font-size: 11px;
  }
  .count {
    font-size: 11px;
    font-weight: 500;
    color: var(--secondary-label);
  }
  .spacer {
    flex: 1;
  }
  .progress {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .secondary {
    color: var(--secondary-label);
  }
  .body {
    display: grid;
    grid-template-columns: minmax(360px, 1fr) minmax(400px, 1fr);
    flex: 1;
    min-height: 0;
    gap: 8px;
    margin-top: 12px;
  }
  .list {
    display: flex;
    min-width: 0;
    min-height: 0;
    border: 1px solid var(--separator);
    overflow: hidden;
    font-size: 12px;
  }
  .text {
    white-space: pre;
  }
  .category {
    font-size: 12px;
    font-weight: 600;
  }
  .badge {
    font: 11px var(--font-mono);
  }
  .site-label {
    font: 500 11px var(--font-mono);
  }
  .source-kind {
    font-size: 10px;
    font-weight: 600;
    color: var(--tertiary-label);
  }
  .flow {
    display: flex;
    flex-direction: column;
    gap: 8px;
    min-width: 0;
    min-height: 0;
  }
  .caption {
    font-size: 11px;
    min-height: 14px;
  }
  .diagram {
    flex: 1;
    min-height: 360px;
    position: relative;
  }
</style>
