<script lang="ts">
  // "Pull Request Changes" (`PRDiffWindowController`): the changed files' patches, with a picker. Its content is
  // set by `showPullRequestChanges` through `changesView`.
  import PopUp from "../../../lib/ui/PopUp.svelte";
  import { showFileInMainWindow } from "../../main/navigation";
  import { changesPickerItems, isHighlighted, NO_CHANGES_VALUE } from "./diffLines";
  import { changesView } from "./review.svelte";

  let {}: { windowId: number } = $props();

  const changes = $derived(changesView.changes);
  const items = $derived(changes ? changesPickerItems(changes) : []);
  const selected = $derived(changes?.files[changesView.index] ?? null);
  const pickerValue = $derived(changes && changes.files.length > 0 ? String(changesView.index) : NO_CHANGES_VALUE);

  /** Picking a file shows it in the main window's source viewer, as the changes window's `onOpenFile` does. */
  function pick(value: string) {
    const index = Number(value);
    const file = changes?.files[index];
    if (!file) return;
    changesView.index = index;
    showFileInMainWindow(file.absolutePath);
  }
</script>

{#if changes}
  <div class="changes">
    <div class="bar">
      <PopUp items={items} value={pickerValue} onChange={pick} />
      <span class="summary">{selected?.summary ?? ""}</span>
    </div>
    <div class="patch-box">
      {#if selected}
        <pre class="patch selectable">{#each selected.lines as line, i (i)}<span class="line {line.kind}" class:highlighted={isHighlighted(line)}>{line.text}{"\n"}</span>{/each}</pre>
      {:else}
        <pre class="patch">{changes.emptyMessage}</pre>
      {/if}
    </div>
  </div>
{/if}

<style>
  .changes {
    display: flex;
    flex-direction: column;
    height: 100%;
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
    min-width: 0;
  }
  .summary {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 11px;
    color: var(--secondary-label);
  }
  .patch-box {
    flex: 1;
    min-height: 0;
    margin: 0 12px 12px;
    background: var(--text-bg);
    border: 1px solid var(--bezel-border);
    overflow: auto;
  }
  .patch {
    margin: 0;
    padding: 8px;
    font-family: var(--font-mono);
    font-size: 11px;
    line-height: 1.35;
    white-space: pre-wrap;
    color: var(--label);
  }
  .line.hunk {
    color: var(--secondary-label);
  }
  .line.added {
    color: var(--system-green);
  }
  .line.removed {
    color: var(--system-red);
  }
  .line.meta {
    color: var(--tertiary-label);
  }
  .line.highlighted {
    background: color-mix(in srgb, var(--system-yellow) 28%, transparent);
    font-weight: 700;
  }
</style>
