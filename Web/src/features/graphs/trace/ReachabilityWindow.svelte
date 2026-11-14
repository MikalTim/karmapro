<script lang="ts">
  // The reachability window's content: the title and caption over the call
  // diagram (the same `DataFlowDiagram` the data-flow window uses), with the
  // progress or spinner centred over the canvas while the work runs.
  import { DataFlowDiagram } from "../flow";
  import ProgressBar from "../../../lib/ui/ProgressBar.svelte";
  import Spinner from "../../../lib/ui/Spinner.svelte";
  import { openGraphNode } from "./graphNode";
  import { reachability } from "./reachability.svelte";

  // The window system passes its id; this window has nothing to do with it.
  let { windowId: _windowId }: { windowId: number } = $props();
</script>

<div class="reach-window">
  <div class="header">
    <div class="title">{reachability.heading}</div>
    <div class="caption">{reachability.caption}</div>
  </div>
  <div class="canvas">
    {#if reachability.graph}
      {@const graph = reachability.graph}
      <div class="plot">
        <DataFlowDiagram {graph} onNodeClick={(name: string) => openGraphNode(graph, name)} />
      </div>
    {/if}
    {#if reachability.busy}
      <div class="busy">
        {#if reachability.busy.kind === "analysing"}
          <Spinner size={32} />
          <div class="busy-label">Analysing…</div>
        {:else}
          <div class="busy-label">{reachability.busy.label}</div>
          <div class="bar">
            <ProgressBar value={reachability.busy.fraction} width={32} />
          </div>
        {/if}
      </div>
    {/if}
  </div>
</div>

<style>
  .reach-window {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
    background: var(--window-bg);
  }
  .header {
    flex: none;
    padding: 16px 20px 0;
  }
  .title {
    font-size: 16px;
    font-weight: 600;
    color: var(--label);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .caption {
    margin-top: 4px;
    font-size: 12px;
    color: var(--secondary-label);
    white-space: pre-line;
  }
  .canvas {
    position: relative;
    flex: 1;
    min-height: 0;
    margin-top: 10px;
    background: var(--control-bg);
    overflow: hidden;
  }
  .plot {
    position: absolute;
    inset: 0;
  }
  .busy {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    pointer-events: none;
  }
  .busy-label {
    max-width: 90%;
    font-size: 18px;
    font-weight: 600;
    color: var(--label);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .bar {
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
  }
</style>
