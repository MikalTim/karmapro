<script lang="ts">
  // The complexity window's content: the summary, the hover line and the chart.
  // While the project scan runs, a spinner and its caption cover the chart.
  import Spinner from "../../../lib/ui/Spinner.svelte";
  import ComplexityScatter from "./ComplexityScatter.svelte";
  import { complexity } from "./complexity.svelte";
  import { hoverText } from "./complexityModel";
  import type { ComplexityPointDTO } from "./dto";

  // The window system passes its id; this window has nothing to do with it.
  let { windowId: _windowId }: { windowId: number } = $props();

  let hover = $state("");

  function showHover(point: ComplexityPointDTO | null): void {
    hover = point ? hoverText(point) : "";
  }
</script>

<div class="complexity-window">
  <div class="summary">{complexity.summary}</div>
  <div class="hover">{hover}</div>
  <div class="chart">
    <ComplexityScatter points={complexity.points} placeholder={complexity.placeholder} onHover={showHover} />
    {#if complexity.analysing}
      <div class="analysing">
        <Spinner size={40} />
        <div class="analysing-label">Analyzing complexity distribution…</div>
      </div>
    {/if}
  </div>
</div>

<style>
  .complexity-window {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
    background: var(--window-bg);
  }
  .summary {
    flex: none;
    padding: 14px 16px 0;
    font-size: 13px;
    font-weight: 600;
    color: var(--label);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .hover {
    flex: none;
    padding: 4px 16px 0;
    font-size: 11px;
    color: var(--secondary-label);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .chart {
    position: relative;
    flex: 1;
    min-height: 0;
    margin-top: 8px;
    display: flex;
  }
  .analysing {
    position: absolute;
    left: 50%;
    top: 50%;
    transform: translate(-50%, -50%);
    margin-top: -16px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    pointer-events: none;
  }
  .analysing-label {
    font-size: 14px;
    color: var(--secondary-label);
    white-space: nowrap;
  }
</style>
