<script lang="ts">
  // The window shown while the project's index is built (`IndexBuildWindowController`).
  // It floats over the page without a close button, can be moved by its title bar, and
  // leaves when the build ends.
  import ProgressBar from "../../lib/ui/ProgressBar.svelte";
  import { indexFraction, indexStatus } from "./indexProgress";
  import MiddleText from "./MiddleText.svelte";
  import type { IndexBuild } from "./projectState.svelte";

  let { build }: { build: IndexBuild } = $props();

  // The estimate is worked out when a progress report arrives, as AppKit's update does.
  const status = $derived(
    build.progressed
      ? indexStatus(build.done, build.total, (Date.now() - build.startedAt) / 1000)
      : `Indexing ${build.projectName}…`,
  );

  // The window moves with its title bar, as a titled window does.
  let offsetX = $state(0);
  let offsetY = $state(0);

  function dragStart(event: PointerEvent): void {
    event.preventDefault();
    const startX = event.clientX - offsetX;
    const startY = event.clientY - offsetY;
    const move = (moved: PointerEvent) => {
      offsetX = moved.clientX - startX;
      offsetY = moved.clientY - startY;
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  }
</script>

<div class="sheet" style:transform="translate(calc(-50% + {offsetX}px), calc(-50% + {offsetY}px))">
  <div class="title" role="presentation" onpointerdown={dragStart}>Building project's index</div>
  <div class="body">
    <div class="bar-row"><ProgressBar value={indexFraction(build.done, build.total)} /></div>
    <div class="status" role="status"><MiddleText text={status} /></div>
  </div>
</div>

<style>
  /* The bar's cell is 20 px tall with the track in its middle, and the label sits 8 px below it. */
  .bar-row {
    display: flex;
    align-items: center;
    height: 20px;
  }
  .sheet {
    position: fixed;
    left: 50%;
    top: 50%;
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
  /* The window's content area is 96 px tall (`contentRect` 360 x 96), with 20 px above the bar and at its sides. */
  .body {
    box-sizing: border-box;
    height: 96px;
    padding: 20px 20px 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .status {
    display: flex;
    font-size: 11px;
    color: var(--secondary-label);
  }
</style>
