<script lang="ts">
  // The window shown while the project's index is built (`IndexBuildWindowController`).
  // It floats over the page without a close button and leaves when the build ends.
  import ProgressBar from "../../lib/ui/ProgressBar.svelte";
  import { indexFraction, indexStatus } from "./indexProgress";
  import type { IndexBuild } from "./projectState.svelte";

  let { build }: { build: IndexBuild } = $props();

  // The estimate is worked out when a progress report arrives, as AppKit's update does.
  const status = $derived(
    build.progressed
      ? indexStatus(build.done, build.total, (Date.now() - build.startedAt) / 1000)
      : `Indexing ${build.projectName}…`,
  );
</script>

<div class="sheet">
  <div class="title">Building project's index</div>
  <div class="body">
    <ProgressBar value={indexFraction(build.done, build.total)} />
    <div class="status" role="status">{status}</div>
  </div>
</div>

<style>
  .sheet {
    position: fixed;
    left: 50%;
    top: 50%;
    transform: translate(-50%, -50%);
    width: 360px;
    z-index: 60000;
    background: var(--window-bg);
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 10px;
    box-shadow: var(--shadow);
    overflow: hidden;
  }
  .title {
    height: 28px;
    line-height: 28px;
    text-align: center;
    font-size: 13px;
    font-weight: 600;
    color: var(--label);
    background: #323234;
    border-bottom: 1px solid rgba(0, 0, 0, 0.5);
  }
  .body {
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .status {
    font-size: 11px;
    color: var(--secondary-label);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
