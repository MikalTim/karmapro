<script lang="ts">
  import { untrack } from "svelte";
  // The prompt template editor (AIWindowController.showPromptEditor): an alert
  // with a title field and a text editor, shown as a sheet of the AI window.
  import Sheet from "../../../lib/ui/Sheet.svelte";
  import TextArea from "../../../lib/ui/TextArea.svelte";
  import TextField from "../../../lib/ui/TextField.svelte";
  import { addPrompt, reportError, updatePrompt } from "./assistantStore.svelte";
  import type { AIPrompt } from "./types";

  let {
    windowId,
    existing,
    onClose,
  }: { windowId: number; existing: AIPrompt | null; onClose: () => void } = $props();

  // The editor starts from the template being edited; later edits stay local to the sheet.
  let title = $state(untrack(() => existing?.title ?? ""));
  let text = $state(untrack(() => existing?.promptText ?? ""));
  const heading = $derived(existing ? "Edit Prompt" : "New Prompt");

  // An empty title closes the editor without saving, as the AppKit alert does.
  async function save(): Promise<void> {
    const trimmedTitle = title.trim();
    if (trimmedTitle !== "") {
      try {
        if (existing) {
          await updatePrompt(existing.id, trimmedTitle, text.trim());
        } else {
          await addPrompt(trimmedTitle, text.trim());
        }
      } catch (error) {
        reportError(error);
      }
    }
    onClose();
  }

  // Escape cancels the alert. Its event is stopped here so the AI window stays open.
  function keydown(event: KeyboardEvent): void {
    if (event.key !== "Escape") return;
    event.preventDefault();
    onClose();
  }
</script>

<Sheet {windowId} width={472}>
  <div class="sheet" role="dialog" tabindex="-1" aria-label={heading} onkeydown={keydown}>
    <div class="message">{heading}</div>
    <div class="informative">The title appears in the dropdown; selecting it pastes the prompt text into the editor.</div>
    <div class="label">Title:</div>
    <div class="wide">
      <TextField
        bind:value={title}
        placeholder={'Menu title, e.g. "Audit Auth Code"'}
        autofocus
        onEnter={save}
      />
    </div>
    <div class="label">Prompt text:</div>
    <div class="body">
      <TextArea bind:value={text} />
    </div>
    <div class="buttons">
      <button class="btn" onclick={onClose}>Cancel</button>
      <button class="btn default" onclick={save}>Save</button>
    </div>
  </div>
</Sheet>

<style>
  .sheet {
    display: flex;
    flex-direction: column;
    gap: 8px;
    font-family: var(--font-ui);
    color: var(--label);
  }
  .message {
    font-size: 13px;
    font-weight: 700;
  }
  .informative {
    font-size: 11px;
    color: var(--secondary-label);
  }
  .label {
    font-size: 13px;
    margin-top: 4px;
  }
  .wide {
    display: flex;
  }
  .wide :global(.field) {
    flex: 1;
    min-width: 0;
  }
  .body {
    display: flex;
    height: 220px;
  }
  .body :global(.field) {
    font-size: 13px;
  }
  .buttons {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 8px;
  }
</style>
