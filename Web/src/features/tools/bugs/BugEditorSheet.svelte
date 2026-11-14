<script lang="ts">
  // The bug report editor (BugEditorWindowController), a sheet of the bug list as in AppKit
  // (`parent.beginSheet`). Opened with an `id` it edits that report; without one it starts a new
  // report from the server's defaults. The preset title menu only appears for new reports.
  import { onMount } from "svelte";
  import { api } from "../../../lib/api";
  import PopUp from "../../../lib/ui/PopUp.svelte";
  import Sheet from "../../../lib/ui/Sheet.svelte";
  import TextArea from "../../../lib/ui/TextArea.svelte";
  import TextField from "../../../lib/ui/TextField.svelte";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import {
    buildBugInput,
    formFromBug,
    messageOf,
    newBugForm,
    presetFill,
    type BugChoicesDTO,
    type BugDTO,
    type BugInput,
    type BugListDTO,
  } from "./bugModel";

  let {
    windowId,
    id,
    onSaved,
    onClose,
  }: { windowId: number; id?: string; onSaved?: (bug: BugDTO) => void; onClose: () => void } = $props();

  let choices = $state<BugChoicesDTO | null>(null);
  let existing = $state<BugDTO | null>(null);
  let form = $state<BugInput | null>(null);
  let errorText = $state("");
  let presetChoice = $state("0");
  let titleWrap: HTMLDivElement | undefined = $state();
  let dialog: HTMLDivElement | undefined = $state();

  const heading = $derived(id === undefined ? "New Bug Report" : "Edit Bug Report");
  const severityItems = $derived((choices?.severities ?? []).map((title) => ({ title })));
  const statusItems = $derived((choices?.statuses ?? []).map((title) => ({ title })));
  // Index 0 is "Custom title…"; preset n is menu index n + 1 (see `presetFill`).
  const presetItems = $derived([
    { title: "Custom title…", value: "0" },
    ...(choices?.presets ?? []).map((preset, index) => ({ title: preset.title, value: String(index + 1) })),
  ]);

  async function load(): Promise<void> {
    try {
      const loaded = await api<BugChoicesDTO>("GET", "/api/bugs/choices");
      choices = loaded;
      if (id === undefined) {
        form = newBugForm(loaded.defaults);
        return;
      }
      // The API has no single-report read; the full list holds every report.
      const all = await api<BugListDTO>("GET", "/api/bugs");
      const bug = all.bugs.find((candidate) => candidate.id === id);
      if (!bug) {
        await showAlert({ message: "The bug report no longer exists.", buttons: ["OK"], sheetOf: windowId });
        onClose();
        return;
      }
      existing = bug;
      form = formFromBug(bug);
    } catch (error) {
      errorText = messageOf(error);
    }
  }

  // titleMenuItemSelected: the preset fills the title, and its description when it has one.
  function choosePreset(value: string): void {
    const fill = presetFill(choices?.presets ?? [], Number(value));
    if (!form || !fill) return;
    form.title = fill.title;
    if (fill.description !== null) form.detail = fill.description;
    const input = titleWrap?.querySelector<HTMLInputElement>("input");
    input?.focus();
    input?.select();
  }

  async function save(): Promise<void> {
    if (!form) return;
    const built = buildBugInput(form);
    if ("error" in built) {
      errorText = built.error;
      return;
    }
    errorText = "";
    try {
      const saved = existing
        ? await api<BugDTO>("PUT", `/api/bugs/${existing.id}`, built.input)
        : await api<BugDTO>("POST", "/api/bugs", built.input);
      onSaved?.(saved);
      onClose();
    } catch (error) {
      errorText = messageOf(error);
    }
  }

  // Escape is the Cancel button's key equivalent. The event stops here so the list window stays open.
  function keydown(event: KeyboardEvent): void {
    if (event.key !== "Escape") return;
    event.preventDefault();
    onClose();
  }

  onMount(() => {
    void load();
    dialog?.focus();
  });
</script>

<Sheet {windowId} width={528}>
  <div class="editor" role="dialog" tabindex="-1" aria-label={heading} bind:this={dialog} onkeydown={keydown}>
    <div class="heading">{heading}</div>
    {#if form && choices}
      <div class="form">
        {#if id === undefined}
          <div class="row">
            <span class="label">Use preset title:</span>
            <PopUp items={presetItems} bind:value={presetChoice} onChange={choosePreset} />
          </div>
        {/if}

        <div class="row">
          <span class="label">Title:</span>
          <div class="grow" bind:this={titleWrap}>
            <TextField
              bind:value={form.title}
              placeholder="Short summary of the issue"
              autofocus
              onEnter={() => void save()}
            />
          </div>
        </div>

        <div class="row">
          <span class="label">Severity:</span>
          <PopUp items={severityItems} bind:value={form.severity} />
        </div>

        <div class="row">
          <span class="label">Exploitability:</span>
          <PopUp items={severityItems} bind:value={form.exploitability} />
        </div>

        <div class="row">
          <span class="label">Package:</span>
          <TextField bind:value={form.packageName} placeholder="e.g. com.example.app" onEnter={() => void save()} />
        </div>

        <div class="row">
          <span class="label">Version:</span>
          <TextField bind:value={form.version} placeholder="e.g. 1.0.3" onEnter={() => void save()} />
        </div>

        <div class="row">
          <span class="label">Status:</span>
          <PopUp items={statusItems} bind:value={form.status} />
        </div>

        <div class="row top">
          <span class="label">Description:</span>
          <div class="description">
            <TextArea bind:value={form.detail} />
          </div>
        </div>
      </div>

      <div class="error">{errorText}</div>

      <div class="buttons">
        <button class="btn" onclick={onClose}>Cancel</button>
        <button class="btn default" onclick={() => void save()}>Save</button>
      </div>
    {:else if errorText}
      <div class="error">{errorText}</div>
    {/if}
  </div>
</Sheet>

<style>
  .editor {
    box-sizing: border-box;
    height: 572px;
    padding: 0 0 0;
    display: flex;
    flex-direction: column;
    gap: 10px;
    font: 13px var(--font-ui);
    color: var(--label);
  }
  .heading {
    text-align: center;
    font-size: 13px;
    font-weight: 600;
    padding: 2px 0 6px;
  }
  .form {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .row {
    display: grid;
    grid-template-columns: 110px minmax(0, 1fr);
    column-gap: 8px;
    align-items: center;
  }
  .row.top {
    align-items: start;
  }
  .label {
    text-align: right;
    font-weight: 500;
    padding-top: 2px;
  }
  .row.top .label {
    padding-top: 4px;
  }
  .grow {
    min-width: 0;
  }
  .description {
    display: flex;
    height: 220px;
  }
  .error {
    min-height: 18px;
    margin-left: 118px;
    font-size: 12px;
    color: var(--system-red);
  }
  .buttons {
    margin-top: auto;
    display: flex;
    justify-content: flex-end;
    gap: 10px;
  }
  .buttons .btn {
    min-width: 90px;
  }
</style>
