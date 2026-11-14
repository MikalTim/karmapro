<script lang="ts">
  // The debugger simulation (`SimDebugWindowController`): the source of the simulated
  // function with its current line, the parameters, the variables of the selected
  // frame and the call stack.
  import CodeView from "../../../lib/code/CodeView.svelte";
  import type { TokenRange } from "../../../lib/code/decorations";
  import Table, { type Column } from "../../../lib/ui/Table.svelte";
  import { showFileInMainWindow } from "../../main/navigation";
  import {
    focusRange,
    frameColor,
    frameLabel,
    lineRange,
    playButtonTitle,
    watchNameStyle,
    type SimFrame,
    type SimParameter,
    type SimWatchRow,
  } from "./simModel";
  import {
    loadSimSource,
    resetSimulation,
    selectSimFrame,
    setSimParameter,
    sim,
    stepSimulation,
    togglePlaying,
  } from "./simSession.svelte";

  let { windowId }: { windowId: number } = $props();

  interface CodeSource {
    text: string;
    tokens: readonly TokenRange[];
  }

  interface WatchRowView extends SimWatchRow {
    key: string;
  }

  const snapshot = $derived(sim.state);

  // The file's own text and tokens go together; the state's text stands in until they load.
  const code = $derived.by((): CodeSource => {
    const file = sim.source;
    if (file && snapshot && file.path === snapshot.displayedPath) return { text: file.text, tokens: file.tokens };
    return { text: snapshot?.sourceText ?? "", tokens: [] };
  });
  const currentLine = $derived(snapshot && snapshot.currentLine > 0 ? lineRange(code.text, snapshot.currentLine) : null);
  const matches = $derived(currentLine ? [currentLine] : []);
  const focus = $derived(snapshot ? focusRange(snapshot, code.text) : null);

  const parameterColumns: Column<SimParameter>[] = [
    { id: "pname", title: "Parameter", width: 160, style: () => "color: var(--secondary-label)" },
    { id: "pvalue", title: "Value", width: 180 },
  ];
  const watchColumns: Column<WatchRowView>[] = [
    { id: "name", title: "Name", width: 150, value: (row) => row.name, style: watchNameStyle },
    { id: "value", title: "Value", width: 260, value: (row) => row.value },
  ];
  const frameColumns: Column<SimFrame>[] = [
    { id: "frame", title: "Frame", width: 340, value: frameLabel, style: frameColor },
  ];

  const watchRows = $derived<WatchRowView[]>(
    (snapshot?.watchRows ?? []).map((row, index) => ({ ...row, key: String(index) })),
  );

  let codeView: { revealRange(location: number, length: number): void } | undefined = $state();

  // The current line scrolls into view without selecting its text.
  $effect(() => {
    if (currentLine && codeView) codeView.revealRange(currentLine.location, 0);
  });

  // Loads the file the source pane shows whenever the simulation enters another file.
  $effect(() => {
    const path = snapshot?.displayedPath;
    if (path) void loadSimSource(path);
  });

  function commitParameter(parameter: SimParameter, text: string) {
    if (text === parameter.value) return;
    void setSimParameter(parameter.index, text);
  }

  function openFrame(frame: SimFrame) {
    showFileInMainWindow(frame.path, frame.line);
  }
</script>

{#if snapshot}
  <div class="sim">
    <div class="toolbar">
      <div class="badge">{snapshot.badge}</div>
      <button type="button" disabled={!snapshot.canStepOver} onclick={() => stepSimulation("over")}>Step Over</button>
      <button type="button" disabled={!snapshot.canStepInto} onclick={() => stepSimulation("into")}>Step Into</button>
      <button type="button" disabled={!snapshot.canStepBack} onclick={() => stepSimulation("back")}>Step Back</button>
      <button type="button" disabled={!snapshot.canReset} onclick={() => resetSimulation()}>Reset</button>
      <button type="button" disabled={!snapshot.canPlay} onclick={togglePlaying}>{playButtonTitle(sim.playing)}</button>
      <div class="status">{snapshot.statusText}</div>
    </div>

    <div class="panes">
      <div class="source">
        <CodeView bind:this={codeView} source={code.text} tokens={code.tokens} {matches} {focus} />
      </div>

      <div class="side">
        <div class="label">Parameters (editable)</div>
        <div class="parameters">
          <Table columns={parameterColumns} rows={snapshot.parameters} rowKey={(row) => String(row.index)} rowHeight={20}>
            {#snippet cell(row, column)}
              {#if column.id === "pvalue"}
                <input
                  class="value-input"
                  value={row.value}
                  onchange={(event) => commitParameter(row, event.currentTarget.value)}
                  onkeydown={(event) => event.stopPropagation()}
                />
              {:else}
                {row.summary}
              {/if}
            {/snippet}
          </Table>
        </div>

        <div class="label">Variables</div>
        <div class="watch">
          <Table columns={watchColumns} rows={watchRows} rowKey={(row) => row.key} rowHeight={20} />
        </div>

        <div class="label">Call Stack</div>
        <div class="stack">
          <Table
            columns={frameColumns}
            rows={snapshot.frames}
            rowKey={(row) => String(row.index)}
            selectedKey={String(snapshot.selectedFrameIndex)}
            rowHeight={20}
            onSelect={(row) => {
              if (row) void selectSimFrame(row.index);
            }}
            onDoubleClick={openFrame}
          />
        </div>
      </div>
    </div>
  </div>
{/if}

<style>
  .sim {
    display: flex;
    flex-direction: column;
    height: 100%;
    box-sizing: border-box;
    background: var(--window-bg);
    color: var(--label);
    font: 13px var(--font-ui);
  }
  .toolbar {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 38px;
    padding: 0 12px;
    box-sizing: border-box;
  }
  .badge {
    padding: 3px 8px;
    border-radius: 6px;
    background: color-mix(in srgb, var(--accent) 18%, transparent);
    font: 12px var(--font-mono);
    white-space: nowrap;
  }
  button {
    font: 13px var(--font-ui);
    color: var(--label);
    background: rgba(255, 255, 255, 0.08);
    border: 1px solid var(--separator);
    border-radius: 5px;
    padding: 3px 10px;
    cursor: pointer;
  }
  button:disabled {
    color: var(--tertiary-label);
    cursor: default;
  }
  .status {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 11px;
    color: var(--secondary-label);
  }
  .panes {
    display: grid;
    grid-template-columns: minmax(300px, 1fr) 420px;
    flex: 1;
    min-height: 0;
    gap: 8px;
    margin-top: 8px;
  }
  .source {
    min-width: 0;
    min-height: 200px;
    border-top: 1px solid var(--separator);
    overflow: hidden;
    font: 12px var(--font-mono);
  }
  .side {
    display: flex;
    flex-direction: column;
    gap: 5px;
    min-width: 0;
    min-height: 0;
    padding-right: 12px;
  }
  .label {
    font-size: 11px;
    font-weight: 700;
    color: var(--secondary-label);
  }
  .parameters {
    height: 110px;
    flex: none;
    font-size: 11px;
  }
  .watch {
    flex: 1;
    min-height: 120px;
    font-size: 11px;
  }
  .stack {
    height: 180px;
    flex: none;
    font-size: 11px;
  }
  .value-input {
    width: 100%;
    box-sizing: border-box;
    border: none;
    background: transparent;
    color: var(--label);
    font: 11px var(--font-ui);
    padding: 0;
    outline: none;
  }
</style>
