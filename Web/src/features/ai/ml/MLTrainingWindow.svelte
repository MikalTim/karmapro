<script lang="ts">
  // Train Bayesian Classifier (`MLTrainingWindowController`): pick a folder of
  // patches, name a model, train it on the +/- lines, and export, import or
  // download models.
  import { api, download, upload } from "../../../lib/api";
  import { on } from "../../../lib/events";
  import { runJob } from "../../../lib/jobs";
  import { showAlert, showAlertWithFields } from "../../../lib/ui/alert.svelte";
  import { pickPath } from "../../../lib/ui/directoryPicker.svelte";
  import { chooseFile } from "../../../lib/ui/fileUpload";
  import PopUp from "../../../lib/ui/PopUp.svelte";
  import ProgressBar from "../../../lib/ui/ProgressBar.svelte";
  import TextField from "../../../lib/ui/TextField.svelte";
  import ExportModelSheet from "./ExportModelSheet.svelte";
  import {
    DOWNLOADING_STATUS,
    IMPORT_URL_PROMPT,
    READING_PATCHES_STATUS,
    exportFailedAlert,
    exportProblem,
    exportedAlert,
    importFailedAlert,
    importedAlert,
    importedFromURLStatus,
    keptChoice,
    messageOf,
    modelAddress,
    progressFraction,
    trainRequest,
    type MLModelDTO,
    type MLModelsDTO,
    type MLOptionsDTO,
    type MLTrainResultDTO,
  } from "./mlModel";

  let { windowId }: { windowId: number } = $props();

  let options = $state<MLOptionsDTO | null>(null);
  let models = $state<string[]>([]);
  let folder = $state<string | null>(null);
  let name = $state("");
  let language = $state("");
  let training = $state(false);
  let progress = $state(0);
  let status = $state("");
  let importingURL = $state(false);
  let exporting = $state<string[] | null>(null);
  let root = $state<HTMLElement | null>(null);

  const languageItems = $derived((options?.trainingLanguages ?? []).map((item) => ({ title: item.name })));
  const savedModels = $derived(options?.modelsSummary ?? "");

  async function load() {
    try {
      const list = await api<MLModelsDTO>("GET", "/api/ml/models");
      options = list.options;
      models = list.models.map((model: MLModelDTO) => model.name);
      language = keptChoice(
        language,
        list.options.trainingLanguages.map((item) => item.name),
      );
    } catch (error) {
      status = messageOf(error);
    }
  }

  $effect(() => {
    void load();
    return on("ml.changed", () => void load());
  });

  async function chooseFolder() {
    const picked = await pickPath({ message: "Choose a folder of software patches (.patch / .diff)" });
    if (picked !== null) folder = picked;
  }

  async function train() {
    const request = trainRequest(folder, name, language);
    if ("problem" in request) {
      await showAlert(request.problem);
      return;
    }
    training = true;
    progress = 0;
    status = READING_PATCHES_STATUS;
    try {
      const job = runJob<MLTrainResultDTO>(api<{ jobId: string }>("POST", "/api/ml/train", request.value), (update) => {
        progress = progressFraction(update.done, update.total);
      });
      const outcome = await job.promise;
      if (outcome.result) status = outcome.result.statusText;
    } catch (error) {
      status = messageOf(error);
    } finally {
      training = false;
    }
  }

  async function exportClicked() {
    const problem = exportProblem(models);
    if (problem) {
      await showAlert(problem);
      return;
    }
    exporting = models;
  }

  async function finishExport(chosenName: string | null) {
    exporting = null;
    if (chosenName === null) return;
    try {
      const fileName = await download(`/api/ml/models/${encodeURIComponent(chosenName)}/export`, {
        fallbackName: `${chosenName}.karmamodel`,
      });
      await showAlert(exportedAlert(chosenName, fileName));
    } catch (error) {
      await showAlert(exportFailedAlert(messageOf(error)));
    }
  }

  async function importModel() {
    const file = await chooseFile(".karmamodel,.json");
    if (file === null) return;
    try {
      const model = await upload<MLModelDTO>("/api/ml/models/import", file);
      await showAlert(importedAlert(model.name));
    } catch (error) {
      await showAlert(importFailedAlert(messageOf(error)));
    }
  }

  async function importFromURL() {
    const entered = await showAlertWithFields({
      message: IMPORT_URL_PROMPT.message,
      informative: IMPORT_URL_PROMPT.informative,
      buttons: ["Import", "Cancel"],
      fields: [{ placeholder: IMPORT_URL_PROMPT.placeholder, width: 380 }],
    });
    if (entered.button !== 0) return;
    const address = modelAddress(entered.values[0]);
    if ("problem" in address) {
      await showAlert(address.problem);
      return;
    }
    importingURL = true;
    status = DOWNLOADING_STATUS;
    try {
      const model = await api<MLModelDTO>("POST", "/api/ml/models/import-url", address.value);
      status = importedFromURLStatus(model.name);
    } catch (error) {
      status = messageOf(error);
    } finally {
      importingURL = false;
    }
  }

  // NSButton keyEquivalent "\r": Enter anywhere in this window trains, unless
  // an alert or sheet already answered the key or a button has the focus.
  function keydown(event: KeyboardEvent) {
    if (event.key !== "Enter" || event.defaultPrevented || training) return;
    const target = event.target;
    if (!(target instanceof Node) || !root?.contains(target) || target instanceof HTMLButtonElement) return;
    void train();
  }
</script>

<svelte:window onkeydown={keydown} />

<div class="body" bind:this={root}>
  <div class="intro">
    Point at a folder of software patches (.patch/.diff). Lines starting with “+” are treated as good code; “-” lines as
    bad (vulnerable) code.
  </div>
  <div class="row">
    <button class="btn" onclick={() => void chooseFolder()}>Choose Patch Folder…</button>
    <div class="folder">{folder ?? "No patch folder chosen."}</div>
  </div>
  <div class="row">
    <span class="label">Model name:</span>
    <TextField bind:value={name} placeholder="e.g. CVE-2024-patches" width={320} />
  </div>
  {#if training}
    <div class="progress"><ProgressBar value={progress} /></div>
  {/if}
  <div class="row">
    <span class="label">Language:</span>
    <PopUp items={languageItems} bind:value={language} />
    <button class="btn default" disabled={training} onclick={() => void train()}>Train Model</button>
  </div>
  <div class="row">
    <button class="btn" onclick={() => void exportClicked()}>Export Model…</button>
    <button class="btn" onclick={() => void importModel()}>Import Model…</button>
    <button class="btn" disabled={importingURL} onclick={() => void importFromURL()}>Import from URL…</button>
  </div>
  <div class="status">{status}</div>
  <div class="saved">{savedModels}</div>
</div>

{#if exporting}
  <ExportModelSheet {windowId} names={exporting} onClose={(chosenName) => void finishExport(chosenName)} />
{/if}

<style>
  .body {
    height: 100%;
    box-sizing: border-box;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    color: var(--label);
    overflow: auto;
  }
  .intro {
    font-size: 12px;
    color: var(--secondary-label);
  }
  .row {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .folder {
    flex: 1;
    min-width: 0;
    overflow-wrap: anywhere;
  }
  .progress {
    width: 100%;
  }
  .status {
    font-size: 12px;
    color: var(--secondary-label);
  }
  .saved {
    overflow-wrap: anywhere;
  }
</style>
