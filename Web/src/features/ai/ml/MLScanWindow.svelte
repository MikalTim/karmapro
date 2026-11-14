<script lang="ts">
  // ML Project Scan (`MLScanWindowController`): scans the open project with a
  // trained model, flags the lines whose bad probability reaches the threshold,
  // and then shows the heatmap of the flagged files.
  import { api } from "../../../lib/api";
  import { on } from "../../../lib/events";
  import { runJob } from "../../../lib/jobs";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import PopUp from "../../../lib/ui/PopUp.svelte";
  import ProgressBar from "../../../lib/ui/ProgressBar.svelte";
  import Slider from "../../../lib/ui/Slider.svelte";
  import { openHeatmapWindow } from "./heatmapWindow";
  import {
    hasProjectRoot,
    keptChoice,
    messageOf,
    modelChoice,
    modelPopupTitles,
    progressFraction,
    scanRequest,
    scanningStatus,
    type MLModelsDTO,
    type MLOptionsDTO,
    type MLScanResultDTO,
    type ProjectRootDTO,
  } from "./mlModel";

  let { windowId: _windowId }: { windowId: number } = $props();

  let options = $state<MLOptionsDTO | null>(null);
  let models = $state<string[]>([]);
  let hasRoot = $state(false);
  let modelName = $state("");
  let languageName = $state("");
  let threshold = $state(70);
  let scanning = $state(false);
  let progress = $state(0);
  let status = $state("No scan run yet.");
  let root = $state<HTMLElement | null>(null);
  // The threshold keeps what the user set across refreshes; only the first load takes the default.
  let thresholdTaken = false;

  const canScan = $derived(options?.canScan ?? false);
  const scanEnabled = $derived(canScan && !scanning);
  const modelItems = $derived(modelPopupTitles(models).map((title) => ({ title })));
  const languageItems = $derived((options?.scanLanguages ?? []).map((item) => ({ title: item.name })));

  async function load() {
    try {
      const [list, project] = await Promise.all([
        api<MLModelsDTO>("GET", "/api/ml/models"),
        api<ProjectRootDTO>("GET", "/api/project"),
      ]);
      options = list.options;
      models = list.models.map((model) => model.name);
      hasRoot = hasProjectRoot(project);
      modelName = modelChoice(modelName, models);
      languageName = keptChoice(
        languageName,
        list.options.scanLanguages.map((item) => item.name),
      );
      if (!thresholdTaken) {
        threshold = list.options.thresholdDefault;
        thresholdTaken = true;
      }
    } catch (error) {
      status = messageOf(error);
    }
  }

  $effect(() => {
    void load();
    const offModels = on("ml.changed", () => void load());
    const offWorkspace = on("workspace.changed", () => void load());
    return () => {
      offModels();
      offWorkspace();
    };
  });

  async function scan() {
    const current = options;
    if (current === null || scanning) return;
    const request = scanRequest({
      hasRoot,
      model: modelName,
      languages: current.scanLanguages,
      language: languageName,
      threshold,
    });
    if ("problem" in request) {
      await showAlert(request.problem);
      return;
    }
    scanning = true;
    progress = 0;
    status = scanningStatus(request.value.model);
    try {
      const job = runJob<MLScanResultDTO>(api<{ jobId: string }>("POST", "/api/ml/scan", request.value), (update) => {
        progress = progressFraction(update.done, update.total);
      });
      const outcome = await job.promise;
      if (outcome.result) {
        status = outcome.result.statusText;
        openHeatmapWindow();
      }
    } catch (error) {
      status = messageOf(error);
    } finally {
      scanning = false;
    }
  }

  // NSButton keyEquivalent "\r": Enter anywhere in this window scans while the
  // button is enabled, unless an alert answered the key or a button has the focus.
  function keydown(event: KeyboardEvent) {
    if (event.key !== "Enter" || event.defaultPrevented || !scanEnabled) return;
    const target = event.target;
    if (!(target instanceof Node) || !root?.contains(target) || target instanceof HTMLButtonElement) return;
    void scan();
  }
</script>

<svelte:window onkeydown={keydown} />

<div class="body" bind:this={root}>
  <div class="row">
    <span class="label">Trained model:</span>
    <PopUp items={modelItems} bind:value={modelName} />
  </div>
  <div class="row">
    <span class="label">Language:</span>
    <PopUp items={languageItems} bind:value={languageName} />
  </div>
  <div class="row">
    <span class="label">Flag threshold:</span>
    <Slider
      bind:value={threshold}
      min={options?.thresholdMin ?? 1}
      max={options?.thresholdMax ?? 100}
      step={1}
      width={300}
      format={(value) => `${Math.round(value)}%`}
    />
  </div>
  {#if scanning}
    <div class="progress"><ProgressBar value={progress} /></div>
  {/if}
  <button class="btn default wide" disabled={!scanEnabled} onclick={() => void scan()}>Scan Project</button>
  <div class="status">{status}</div>
  {#if options?.unavailableText}
    <div class="unavailable">{options.unavailableText}</div>
  {/if}
</div>

<style>
  .body {
    height: 100%;
    box-sizing: border-box;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 14px;
    color: var(--label);
    overflow: auto;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .row :global(select) {
    min-width: 220px;
  }
  .row :global(.slider .value) {
    font-size: 12px;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
  }
  .btn.default:disabled {
    background: rgba(10, 132, 255, 0.35);
    color: var(--tertiary-label);
  }
  .progress {
    width: 100%;
  }
  .wide {
    width: 100%;
  }
  .status {
    font-size: 12px;
    color: var(--secondary-label);
  }
  .unavailable {
    overflow-wrap: anywhere;
  }
</style>
