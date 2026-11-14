<script lang="ts">
  // The pane under the source viewer (`FlowPanelViewController`): the cyclomatic complexity, the
  // line count and the callees of the selected function, and its control-flow chart. The server
  // does the analysis; the panel shows the answer for the function it was given.
  import { api, withQuery } from "../../../lib/api";
  import FlowChart from "./FlowChart.svelte";
  import type { FlowDTO } from "./flowModel";

  let {
    path,
    functionName,
    location = null,
  }: { path: string | null; functionName: string | null; location?: number | null } = $props();

  let flow = $state.raw<FlowDTO | null>(null);
  let failure = $state<string | null>(null);
  let chartView = $state<ReturnType<typeof FlowChart>>();

  // Each function change asks for its flowchart; an answer for an earlier function is ignored. The clicked
  // offset lets the server analyse the overload that was clicked, as AppKit passes the clicked definition.
  $effect(() => {
    const target = path;
    const name = functionName;
    const clicked = location;
    flow = null;
    failure = null;
    if (target === null || name === null) return;
    let stale = false;
    const query = { path: target, function: name, location: clicked ?? undefined };
    api<FlowDTO>("GET", withQuery("/api/flow", query)).then(
      (dto) => {
        if (!stale) flow = dto;
      },
      (error: unknown) => {
        if (!stale) failure = error instanceof Error ? error.message : String(error);
      },
    );
    return () => {
      stale = true;
    };
  });

  // Thresholds of `complexityColor(_:)`: green below 5, orange below 10, red below 20.
  function complexityColour(complexity: number): string {
    if (complexity < 5) return "var(--system-green)";
    if (complexity < 10) return "var(--system-orange)";
    if (complexity < 20) return "var(--system-red)";
    return "#733333";
  }

  const header = $derived(functionName ?? "No function selected");
  const badgeText = $derived.by((): string => {
    if (flow === null) return "";
    if (flow.complexity === undefined) return "Cyclomatic complexity: \u2014";
    return `Cyclomatic complexity: ${flow.complexity}`;
  });
  const badgeColour = $derived(
    flow?.complexity === undefined || flow === null ? "var(--secondary-label)" : complexityColour(flow.complexity),
  );
  const linesText = $derived(flow?.lineCount === undefined ? "" : `Lines: ${flow.lineCount}`);
  const callsText = $derived.by((): string => {
    if (failure !== null) return failure;
    if (flow === null || flow.complexity === undefined) return "";
    if (flow.callees.length === 0) return "Functions called: none";
    return `Functions called (${flow.callees.length}): ${flow.callees.join(", ")}`;
  });
</script>

<div class="panel">
  <div class="top">
    <div class="title">{header}</div>
    <button class="btn small" title="Center the flowchart in the panel" onclick={() => chartView?.center()}>Center</button>
  </div>
  <div class="badge" style:color={badgeColour}>{badgeText}</div>
  <div class="meta">{linesText}</div>
  <div class="meta">{callsText}</div>
  <div class="chart-area">
    {#if flow?.chart}
      <FlowChart chart={flow.chart} bind:this={chartView} />
    {/if}
  </div>
  {#if functionName === null}
    <div class="placeholder">Click a function name in the source to see its cyclomatic complexity and logic flowchart.</div>
  {/if}
</div>

<style>
  .panel {
    position: relative;
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
    font: 400 12px var(--font-ui);
  }
  .top {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 14px 0;
  }
  .title {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
    font-size: 13px;
    font-weight: 600;
    color: var(--label);
  }
  .badge {
    height: 20px;
    margin: 8px 14px 0;
    font-size: 13px;
    font-weight: 700;
    line-height: 20px;
    white-space: nowrap;
  }
  .meta {
    min-height: 15px;
    margin: 6px 14px 0;
    color: var(--secondary-label);
    overflow-wrap: anywhere;
  }
  .chart-area {
    flex: 1;
    min-height: 0;
    margin-top: 8px;
  }
  .placeholder {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0 14px;
    text-align: center;
    color: var(--secondary-label);
    pointer-events: none;
  }
</style>
