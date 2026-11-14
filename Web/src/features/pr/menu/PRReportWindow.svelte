<script lang="ts">
  // "Pull Request Review Report" (`PRReportWindowController`): the Markdown report, with Copy and Save As. The
  // report leaves the machine only through the user's own copy or save.
  import { topWindowId } from "../../../lib/ui/windows.svelte";
  import { errorMessage } from "./failures";
  import { reportView } from "./review.svelte";
  import { saveTextFile } from "./saveFile";

  let { windowId }: { windowId: number } = $props();

  const report = $derived(reportView.report);
  const status = $derived(reportView.status ?? { text: report?.statusText ?? "", error: false });

  async function copy(): Promise<void> {
    if (!report) return;
    try {
      await navigator.clipboard.writeText(report.markdown);
      reportView.status = { text: "Copied to the clipboard.", error: false };
    } catch (error) {
      reportView.status = { text: `Could not copy: ${errorMessage(error)}`, error: true };
    }
  }

  function save(): void {
    if (!report) return;
    try {
      saveTextFile(report.suggestedName, report.markdown);
      reportView.status = { text: `Saved to ${report.suggestedName}.`, error: false };
    } catch (error) {
      reportView.status = { text: `Could not save: ${errorMessage(error)}`, error: true };
    }
  }

  /** Return saves, as the Save As button is the window's default button. A focused button keeps its own Return. */
  function keydown(event: KeyboardEvent) {
    if (event.key !== "Enter" || topWindowId() !== windowId || event.target instanceof HTMLButtonElement) return;
    event.preventDefault();
    save();
  }
</script>

<svelte:window onkeydown={keydown} />

{#if report}
  <div class="report">
    <pre class="markdown selectable">{report.markdown}</pre>
    <div class="footer">
      <button class="btn" onclick={() => void copy()}>Copy Markdown</button>
      <button class="btn default" onclick={save}>Save As{"\u2026"}</button>
      <span class="status" class:error={status.error}>{status.text}</span>
    </div>
  </div>
{/if}

<style>
  .report {
    display: flex;
    flex-direction: column;
    height: 100%;
  }
  .markdown {
    flex: 1;
    min-height: 0;
    margin: 12px 12px 0;
    padding: 8px;
    overflow: auto;
    background: var(--text-bg);
    border: 1px solid var(--bezel-border);
    font-family: var(--font-mono);
    font-size: 11px;
    line-height: 1.35;
    white-space: pre-wrap;
    color: var(--label);
  }
  .footer {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px;
  }
  .status {
    flex: 1;
    min-width: 0;
    margin-left: 4px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 11px;
    color: var(--secondary-label);
  }
  .status.error {
    color: var(--system-red);
  }
</style>
