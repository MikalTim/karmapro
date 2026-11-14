<script lang="ts">
  // The class-usage window's content: the title and status over the instantiation
  // diagram. With no instantiations, the message is centred instead.
  import { DataFlowDiagram } from "../flow";
  import { openGraphNode } from "./graphNode";
  import { classUsage } from "./classUsage.svelte";

  // The window system passes its id; this window has nothing to do with it.
  let { windowId: _windowId }: { windowId: number } = $props();
</script>

<div class="usage-window">
  <div class="header">
    <div class="title">{classUsage.heading}</div>
    <div class="status">{classUsage.status}</div>
  </div>
  <div class="canvas">
    {#if classUsage.graph}
      {@const graph = classUsage.graph}
      <div class="plot">
        <DataFlowDiagram {graph} onNodeClick={(name: string) => openGraphNode(graph, name)} />
      </div>
    {:else if classUsage.emptyMessage}
      <div class="empty">{classUsage.emptyMessage}</div>
    {/if}
  </div>
</div>

<style>
  .usage-window {
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
  .status {
    margin-top: 4px;
    font-size: 12px;
    color: var(--secondary-label);
    white-space: pre-line;
  }
  .canvas {
    position: relative;
    flex: 1;
    min-height: 0;
    margin: 10px 20px 12px;
  }
  .plot {
    position: absolute;
    inset: 0;
  }
  .empty {
    position: absolute;
    left: 0;
    right: 0;
    top: 50%;
    transform: translateY(-50%);
    text-align: center;
    font-size: 14px;
    color: var(--secondary-label);
  }
</style>
