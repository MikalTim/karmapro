<script lang="ts">
  // The data-flow window (`DataFlowWindowController`): a heading, a caption and the diagram of one
  // function with its direct callers and callees in its file. The server builds the graph; a file
  // that cannot be read shows its error as the heading, as the window does.
  import { api, withQuery } from "../../../lib/api";
  import DataFlowDiagram from "./DataFlowDiagram.svelte";
  import type { DataFlowDTO } from "./diagramModel";

  // The window host passes `windowId`; this window has nothing to do with it.
  let { path, functionName, windowId: _windowId }: { windowId: number; path: string; functionName: string } = $props();

  let data = $state.raw<DataFlowDTO | null>(null);
  let failure = $state<string | null>(null);

  $effect(() => {
    let stale = false;
    api<DataFlowDTO>("GET", withQuery("/api/dataflow", { path, function: functionName })).then(
      (dto) => {
        if (!stale) data = dto;
      },
      (error: unknown) => {
        if (!stale) failure = error instanceof Error ? error.message : String(error);
      },
    );
    return () => {
      stale = true;
    };
  });

  const heading = $derived(failure ?? data?.title ?? "");
  const caption = $derived(failure === null ? (data?.caption ?? "") : "");
</script>

<div class="window">
  <div class="heading">{heading}</div>
  <div class="caption">{caption}</div>
  <div class="diagram">
    {#if data?.graph}
      <DataFlowDiagram graph={data.graph} />
    {:else if data?.emptyMessage}
      <div class="empty">{data.emptyMessage}</div>
    {/if}
  </div>
</div>

<style>
  .window {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }
  .heading {
    margin: 16px 20px 0;
    font: 600 16px var(--font-ui);
    color: var(--label);
  }
  .caption {
    min-height: 15px;
    margin: 4px 20px 0;
    font: 400 12px var(--font-ui);
    color: var(--secondary-label);
  }
  .diagram {
    position: relative;
    flex: 1;
    min-height: 0;
    margin-top: 12px;
  }
  .empty {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0 40px;
    text-align: center;
    font: 400 14px var(--font-ui);
    color: var(--secondary-label);
  }
</style>
