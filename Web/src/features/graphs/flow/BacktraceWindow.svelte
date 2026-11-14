<script lang="ts">
  // The backtrace analyser (`BacktraceAnalyserWindowController`): paste a stacktrace, Analyse it, and
  // click a frame to open its source at the line. The server parses the text and resolves each file
  // inside the open project; a frame it cannot resolve is drawn red.
  import { api } from "../../../lib/api";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import TextArea from "../../../lib/ui/TextArea.svelte";
  import { showFileInMainWindow } from "../../main/navigation";
  import type { BacktraceDTO, BacktraceFrameDTO } from "./backtraceModel";
  import BacktraceDiagram from "./BacktraceDiagram.svelte";

  // The window host passes `windowId`; this window has nothing to do with it.
  let { windowId: _windowId }: { windowId: number } = $props();

  let text = $state("");
  let status = $state("");
  let frames = $state.raw<BacktraceFrameDTO[]>([]);

  async function analyse(): Promise<void> {
    if (text.trim() === "") {
      status = "Paste a stacktrace first.";
      return;
    }
    try {
      const result = await api<BacktraceDTO>("POST", "/api/backtrace", { text });
      // The diagram and the status line update before the warning, as the window does.
      frames = result.frames;
      status = result.status;
      if (result.warning) {
        await showAlert({
          message: result.warning.messageText,
          informative: result.warning.informativeText,
          buttons: ["OK"],
        });
      }
    } catch (error) {
      // The server answers 400 with the window's own status text for empty or unparsable input.
      status = error instanceof Error ? error.message : String(error);
    }
  }

  function openFrame(frame: BacktraceFrameDTO): void {
    if (frame.path !== undefined) {
      showFileInMainWindow(frame.path, frame.line);
      return;
    }
    void showAlert({
      message: "File not found in the open project",
      informative:
        "This frame references a source file that is not part of the currently open project. Open the matching project and try again.",
      buttons: ["OK"],
    });
  }
</script>

<div class="window">
  <div class="input">
    <TextArea bind:value={text} monospace />
  </div>
  <div class="bar">
    <button class="btn analyse" onclick={analyse}>Analyse</button>
    <div class="status">{status}</div>
  </div>
  <div class="diagram">
    <BacktraceDiagram {frames} onFrameClick={openFrame} />
  </div>
</div>

<style>
  .window {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }
  .input {
    display: flex;
    height: 170px;
    margin: 12px 12px 0;
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 12px;
    margin: 8px 12px 0;
  }
  .analyse {
    width: 120px;
    height: 34px;
    flex: none;
    font: 600 13px var(--font-ui);
  }
  .status {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
    font: 400 11px var(--font-ui);
    color: var(--secondary-label);
  }
  .diagram {
    flex: 1;
    min-height: 0;
    margin-top: 8px;
  }
</style>
