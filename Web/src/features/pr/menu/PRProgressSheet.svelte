<script lang="ts">
  // "Preparing review" (`PRProgressPanelController`): the checkout's progress while a pull request is fetched.
  // Rows have fixed heights, so the text can never overlap the bar; the window is sized from the same heights.
  import ProgressBar from "../../../lib/ui/ProgressBar.svelte";
  import { progressRepoLine, progressTitle } from "./prText";
  import type { PreparingReview } from "./review.svelte";

  let { progress }: { windowId: number; progress: PreparingReview } = $props();
</script>

<div class="sheet">
  <div class="title selectable">{progressTitle(progress.item)}</div>
  <div class="repo">{progressRepoLine(progress.item)}</div>
  <div class="track">
    <ProgressBar value={progress.fraction} />
  </div>
  <div class="stage">{progress.stage}</div>
  <div class="actions">
    <button class="btn" onclick={() => progress.cancel()}>Cancel</button>
  </div>
</div>

<style>
  /* 440 x 163 content, the sum of the row heights below. */
  .sheet {
    display: flex;
    flex-direction: column;
    padding: 18px 20px;
    height: 100%;
  }
  .title,
  .repo,
  .stage {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .title {
    height: 18px;
    font-size: 13px;
    font-weight: 600;
    color: var(--label);
  }
  .repo {
    margin-top: 3px;
    height: 15px;
    font-size: 11px;
    color: var(--secondary-label);
  }
  .track {
    display: flex;
    align-items: center;
    margin-top: 14px;
    height: 12px;
  }
  .stage {
    margin-top: 10px;
    height: 15px;
    font-size: 11px;
    color: var(--secondary-label);
  }
  .actions {
    display: flex;
    justify-content: flex-end;
    margin-top: 16px;
    height: 24px;
  }
  .actions .btn {
    min-width: 84px;
  }
</style>
