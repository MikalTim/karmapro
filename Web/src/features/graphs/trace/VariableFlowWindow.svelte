<script lang="ts">
  // The variable-flow window's content: title, caption, the indexing progress
  // and the diagram. The progress row keeps its place while hidden, as the
  // AppKit stack does.
  import ProgressBar from "../../../lib/ui/ProgressBar.svelte";
  import VariableFlowDiagram from "./VariableFlowDiagram.svelte";
  import { variableFlow } from "./variableFlow.svelte";

  // The window system passes its id; this window has nothing to do with it.
  let { windowId: _windowId }: { windowId: number } = $props();
</script>

<div class="flow-window">
  <div class="header">
    <div class="title">{variableFlow.heading}</div>
    <div class="caption">{variableFlow.caption}</div>
    <div class="progress" class:hidden={variableFlow.progress === null}>
      <ProgressBar value={variableFlow.progress?.fraction ?? 0} />
      <div class="progress-label">{variableFlow.progress?.label ?? ""}</div>
    </div>
  </div>
  <VariableFlowDiagram result={variableFlow.result} />
</div>

<style>
  .flow-window {
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
  .progress {
    display: flex;
    flex-direction: column;
    gap: 4px;
    margin-top: 10px;
  }
  .progress.hidden {
    visibility: hidden;
  }
  .progress-label {
    font-size: 11px;
    color: var(--secondary-label);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .header + :global(.diagram) {
    margin-top: 12px;
  }
</style>
