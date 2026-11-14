<script lang="ts">
  // The strip above the panes while a pull request review is open (`PRBannerView`). It says which pull request
  // is open, so a filtered tree is never mistaken for an ordinary project.
  import { GitPullRequest } from "@lucide/svelte";
  import {
    leavePullRequestReview,
    runPullRequestScan,
    showAllPullRequestFiles,
    showPullRequestChanges,
    showPullRequestReport,
  } from "./reviewActions";
  import { reviewState } from "./review.svelte";

  /** Below this width the subtitle is dropped rather than cut to nothing (`PRBannerView.subtitleMinimumWidth`). */
  const SUBTITLE_MINIMUM_WIDTH = 900;

  const review = $derived(reviewState.value?.review ?? null);
  let width = $state(0);
  const showSubtitle = $derived(width >= SUBTITLE_MINIMUM_WIDTH);
</script>

{#if review}
  <div class="banner" bind:clientWidth={width}>
    <span class="edge"></span>
    <span class="icon"><GitPullRequest size={18} strokeWidth={2} /></span>
    <span class="title" title={review.detail}>{review.title}</span>
    {#if showSubtitle}<span class="subtitle" title={review.detail}>{review.subtitle}</span>{/if}
    <span class="spacer"></span>
    <div class="actions">
      <button class="btn" onclick={() => void runPullRequestScan()}>Run a Scan</button>
      <button class="btn" onclick={() => void showPullRequestChanges()}>Show Changes{"\u2026"}</button>
      <button class="btn" onclick={() => void showPullRequestReport()}>Report{"\u2026"}</button>
      {#if review.showAllAvailable}
        <button class="btn" onclick={() => void showAllPullRequestFiles()}>Show All Files</button>
      {/if}
      <button class="btn" onclick={() => void leavePullRequestReview()}>Close Review</button>
    </div>
  </div>
{/if}

<style>
  .banner {
    position: relative;
    display: flex;
    align-items: center;
    gap: 10px;
    height: 56px;
    padding: 0 12px 0 16px;
    background: var(--control-bg);
    border: 1px solid var(--separator);
    overflow: hidden;
  }
  .edge {
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    width: 3px;
    background: var(--accent);
  }
  .icon {
    display: flex;
    flex: none;
    color: var(--accent);
  }
  .title,
  .subtitle {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .title {
    flex: 0 1 auto;
    font-size: 13px;
    font-weight: 600;
    color: var(--label);
  }
  /* The subtitle gives up width first, as its label has the lowest compression resistance. */
  .subtitle {
    flex: 0 10 auto;
    font-size: 11px;
    color: var(--label);
  }
  .spacer {
    flex: 1;
  }
  .actions {
    display: flex;
    flex: none;
    gap: 8px;
  }
  .actions .btn {
    min-height: 22px;
    font-size: 11px;
    font-weight: 500;
  }
</style>
