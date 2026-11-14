<script lang="ts">
  // The source viewer (AppKit `SourceViewer`): one file with its syntax colours, clickable names and call sites,
  // find bar, focus mode, flow arrows, note gutter, ML highlights, the function dataflow pane and the right-click
  // menu. The file's text, names and marks come from the server; this component decides what to show and what each
  // click does. Its public surface is listed in index.ts.
  import { onMount, tick } from "svelte";
  import { EditorView } from "@codemirror/view";
  import CodeView from "../../lib/code/CodeView.svelte";
  import type { ClickTarget } from "../../lib/code/editor";
  import type { TextRange } from "../../lib/code/decorations";
  import type { FlowArrow } from "../../lib/code/flowArrows";
  import { on } from "../../lib/events";
  import { showAlert } from "../../lib/ui/alert.svelte";
  import { type MenuItem, showMenuAt } from "../../lib/ui/contextMenu.svelte";
  import SearchField from "../../lib/ui/SearchField.svelte";
  import { openAIWindow } from "../ai";
  import {
    DataFlowDiagram,
    openBacktraceWindow,
    openClassUsageWindow,
    openComplexityWindow,
    openDataFlowWindow,
    openEntryPointsWindow,
    openReachabilityWindow,
    openSimDebugWindow,
    openVariableFlowWindow,
  } from "../graphs";
  import { NotePopover } from "../tools";
  import { openDefinitionText } from "./definition";
  import HighlightedLines from "./HighlightedLines.svelte";
  import TunnelBar from "./TunnelBar.svelte";
  import TypeTooltip from "./TypeTooltip.svelte";
  import {
    type ContextMenuDTO,
    type DataFlowDTO,
    type FileDTO,
    type FocusDTO,
    loadContextMenu,
    loadDataFlow,
    loadFile,
    loadFlowArrows,
    loadFocus,
    loadTypeAt,
    resolveCall,
  } from "./sourceApi";
  import {
    type ViewerMenuId,
    type ViewportRect,
    errorText,
    findCountLabel,
    findMatches,
    flowArrowsFrom,
    howToFixPrompt,
    nextMatchIndex,
    riskLinesFrom,
    tokenRanges,
    typeLanguageSupported,
    viewerMenuEntries,
  } from "./sourceModel";

  let {
    onShown,
    onFunctionSelected,
  }: {
    /** Called after every `display`, whichever caller asked for it. */
    onShown?: (path: string) => void;
    /** Called when a function name in the code is clicked. */
    onFunctionSelected?: (path: string, functionName: string) => void;
  } = $props();

  /** The part of `CodeView` this viewer calls. */
  interface CodeHandle {
    scrollToLine(line: number): void;
    revealRange(location: number, length: number): void;
  }

  /** The fields of the `job.finished` event this viewer reads. */
  interface JobFinished {
    kind: string;
    status: string;
  }

  const MIN_FLOW_HEIGHT = 150;
  const MIN_SOURCE_HEIGHT = 160;
  const TYPE_LOOKUP_DELAY_MS = 120;
  const IS_MAC = typeof navigator !== "undefined" && navigator.userAgent.includes("Mac");

  let shownPath = $state<string | null>(null);
  let file = $state.raw<FileDTO | null>(null);
  let loadError = $state<string | null>(null);
  let arrows = $state.raw<FlowArrow[]>([]);
  let arrowsOn = $state(true);
  let focused = $state.raw<FocusDTO | null>(null);
  let flowPane = $state.raw<DataFlowDTO | null>(null);
  let flowHeight = $state(260);
  let findOpen = $state(false);
  let findTerm = $state("");
  let matches = $state.raw<TextRange[]>([]);
  let matchIndex = $state(-1);
  let matchLabel = $state("");
  let tooltip = $state<{ text: string; anchor: ViewportRect } | null>(null);
  let note = $state<{ path: string; line: number; anchor: ViewportRect } | null>(null);

  const riskLines: Record<number, number> = $derived(file ? riskLinesFrom(file.mlLines) : {});
  const tokens = $derived(file ? tokenRanges(file.tokens) : []);
  const markedLines = $derived(file ? file.noteLines : []);
  const shownArrows = $derived(arrowsOn ? arrows : []);
  const focusRange = $derived<TextRange | null>(
    focused ? { location: focused.bodyLocation, length: focused.bodyLength } : null,
  );
  const callers = $derived(focused ? focused.callers : []);
  const callees = $derived(focused ? focused.callees : []);
  const flowGraph = $derived(flowPane?.graph ?? null);
  const flowTitle = $derived(flowPane ? flowPane.title : "");

  let root: HTMLDivElement | undefined;
  let codeHost = $state<HTMLDivElement>();
  let findBar = $state<HTMLDivElement>();
  let code = $state<CodeHandle>();

  /** Bumped by every `display`, so a load that has been overtaken changes nothing. */
  let generation = 0;
  let flowRequest = 0;
  let focusRequest = 0;
  let typeTimer = 0;
  /** The position the type tooltip was last looked up for; -1 when none. */
  let typePending = -1;

  /** The CodeMirror view inside the code area. `CodeView` does not export it, so it is found from its DOM. */
  function editor(): EditorView | null {
    const element = codeHost?.querySelector<HTMLElement>(".cm-editor");
    return element ? EditorView.findFromDOM(element) : null;
  }

  function reportFailure(error: unknown): void {
    void showAlert({ message: errorText(error), style: "warning" });
  }

  /** Shows `path`, scrolled to the 1-based `line` when one is given (`MainWindowController.showFile`). */
  export async function display(path: string, line?: number): Promise<void> {
    const current = ++generation;
    shownPath = path;
    loadError = null;
    flowRequest++;
    focusRequest++;
    focused = null;
    flowPane = null;
    tooltip = null;
    note = null;
    matches = [];
    matchIndex = -1;
    try {
      const [loaded, arrowReply] = await Promise.all([loadFile(path), loadFlowArrows(path)]);
      if (current !== generation) return;
      file = loaded;
      arrows = flowArrowsFrom(arrowReply.arrows);
    } catch (error) {
      if (current !== generation) return;
      file = null;
      loadError = errorText(error);
    }
    onShown?.(path);
    await tick();
    const view = editor();
    if (view) view.scrollDOM.scrollTop = 0;
    if (line !== undefined) code?.scrollToLine(line);
  }

  /** Forgets the shown file (`clear`). */
  export function clear(): void {
    generation++;
    shownPath = null;
    file = null;
    loadError = null;
    arrows = [];
    focused = null;
    flowPane = null;
    tooltip = null;
    note = null;
    matches = [];
    matchIndex = -1;
  }

  export function currentPath(): string | null {
    return shownPath;
  }

  /** Opens the find bar and puts the caret in it (`activateFind`). */
  export function find(): void {
    findOpen = true;
    void tick().then(() => {
      const input = findBar?.querySelector("input");
      input?.focus();
      input?.select();
    });
  }

  function setFindTerm(term: string): void {
    findTerm = term;
    matches = file ? findMatches(file.text, term) : [];
    matchIndex = nextMatchIndex(-1, matches.length);
    matchLabel = findCountLabel(term, matches.length, matchIndex);
    revealMatch();
  }

  function advanceMatch(): void {
    if (matches.length === 0) return;
    matchIndex = nextMatchIndex(matchIndex, matches.length);
    matchLabel = findCountLabel(findTerm, matches.length, matchIndex);
    revealMatch();
  }

  function revealMatch(): void {
    const match = matches[matchIndex];
    if (match) code?.revealRange(match.location, match.length);
  }

  function clearFind(): void {
    findTerm = "";
    matches = [];
    matchIndex = -1;
    matchLabel = "";
    findOpen = false;
  }

  /** Leaves focus mode; answers whether it was on, so Escape is used up only then. */
  function clearFocus(): boolean {
    const wasFocused = focused !== null;
    focusRequest++;
    focused = null;
    return wasFocused;
  }

  async function focusFunction(path: string, name: string): Promise<void> {
    const request = ++focusRequest;
    try {
      const reply = await loadFocus(path, name);
      if (reply === null || request !== focusRequest) return;
      focused = reply;
    } catch (error) {
      reportFailure(error);
    }
  }

  /** A focus chip was clicked: show the chip's file and focus the chip's function there (`onTunnelPivot`). */
  async function pivot(path: string, name: string): Promise<void> {
    await display(path);
    await focusFunction(path, name);
  }

  async function showFunctionDataflow(path: string, name: string): Promise<void> {
    const request = ++flowRequest;
    try {
      const reply = await loadDataFlow(path, name);
      if (request !== flowRequest) return;
      flowPane = reply;
    } catch (error) {
      reportFailure(error);
    }
  }

  async function openCallSite(path: string, name: string): Promise<void> {
    try {
      const definition = await resolveCall(path, name);
      if (definition) openDefinitionText(definition.path, definition.text, definition.line);
    } catch (error) {
      reportFailure(error);
    }
  }

  function onTarget(target: ClickTarget): void {
    const path = shownPath;
    if (path === null) return;
    if (target.kind === "function") {
      void showFunctionDataflow(path, target.name);
      onFunctionSelected?.(path, target.name);
    } else if (target.kind === "class") {
      void openClassUsageWindow({ className: target.name });
    } else {
      void openCallSite(path, target.name);
    }
  }

  function menuItems(menu: ContextMenuDTO, selected: string, path: string): MenuItem[] {
    const name = menu.functionName ?? null;
    const variable = menu.variableName ?? null;
    const actions: Record<ViewerMenuId, () => void> = {
      copy: () => {
        if (selected.length > 0) void navigator.clipboard.writeText(selected);
      },
      flowArrows: () => {
        arrowsOn = !arrowsOn;
      },
      focus: () => {
        if (name !== null) void focusFunction(path, name);
      },
      exitFocus: clearFocus,
      complexity: () => void openComplexityWindow({}),
      flowDiagram: () => {
        if (name !== null) void openDataFlowWindow({ path, functionName: name });
      },
      simulate: () => {
        if (name !== null) void openSimDebugWindow({ path, functionName: name });
      },
      reachability: () => {
        if (name !== null) void openReachabilityWindow({ path, functionName: name });
      },
      followVariable: () => {
        if (variable !== null) openVariableFlowWindow({ path, location: menu.variableFlowLocation, variable });
      },
      backtrace: () => void openBacktraceWindow(),
      entries: () => void openEntryPointsWindow(),
      howToFix: () => openAIWindow({ prompt: howToFixPrompt(path, menu.lineNumber, menu.lineText) }),
    };
    return viewerMenuEntries(menu, IS_MAC).map((entry): MenuItem => {
      if (entry.kind === "separator") return { separator: true };
      return {
        title: entry.title,
        disabled: entry.disabled,
        checked: entry.checked,
        shortcut: entry.shortcut,
        action: actions[entry.id],
      };
    });
  }

  async function openContextMenu(
    info: { pos: number | null; from: number; to: number },
    event: MouseEvent,
  ): Promise<void> {
    const path = shownPath;
    if (path === null || file === null || info.pos === null) return;
    // The gutter is not the text view in AppKit, so it has no text menu.
    if (event.target instanceof Element && event.target.closest(".cm-gutters")) return;
    event.preventDefault();
    const { clientX: x, clientY: y } = event;
    const selected = file.text.slice(info.from, info.to);
    try {
      const menu = await loadContextMenu(
        path,
        info.pos,
        { location: info.from, length: info.to - info.from },
        { flowArrowsOn: arrowsOn, focusActive: focused !== null },
      );
      if (path !== shownPath) return;
      showMenuAt(x, y, menuItems(menu, selected, path));
    } catch (error) {
      reportFailure(error);
    }
  }

  function hideTooltip(): void {
    window.clearTimeout(typeTimer);
    typePending = -1;
    tooltip = null;
  }

  /** Looks up the type under the pointer after a short pause, as the viewer's `mouseMoved` does (`updateTypeTooltip`). */
  function hover(event: MouseEvent): void {
    const path = shownPath;
    if (path === null || file === null || !typeLanguageSupported(file.ext)) return;
    const target = event.target;
    // Clickable names and the gutter never show a type; a popover there would take the next click.
    if (!(target instanceof Element) || target.closest(".cm-gutters") || target.closest("[data-link-kind]")) {
      hideTooltip();
      return;
    }
    const view = editor();
    if (view === null) return;
    const pos = view.posAtCoords({ x: event.clientX, y: event.clientY }, false);
    if (pos === typePending) return;
    typePending = pos;
    window.clearTimeout(typeTimer);
    typeTimer = window.setTimeout(() => {
      void lookupType(path, pos, view);
    }, TYPE_LOOKUP_DELAY_MS);
  }

  async function lookupType(path: string, pos: number, view: EditorView): Promise<void> {
    try {
      const text = await loadTypeAt(path, pos);
      if (path !== shownPath || pos !== typePending) return;
      const rect = view.coordsAtPos(pos);
      if (text === null || text.length === 0 || rect === null) {
        tooltip = null;
        return;
      }
      tooltip = {
        text,
        anchor: { x: rect.left, y: rect.top, width: rect.right - rect.left, height: rect.bottom - rect.top },
      };
    } catch {
      // A failed lookup only means no tooltip, so nothing is reported for every pointer movement.
      tooltip = null;
    }
  }

  /** A line number in the gutter was clicked: open its note (`showNotePopover`). */
  function openNote(line: number): void {
    const path = shownPath;
    const view = editor();
    if (path === null || view === null || line < 1 || line > view.state.doc.lines) return;
    const rect = view.coordsAtPos(view.state.doc.line(line).from);
    if (rect === null) return;
    note = {
      path,
      line,
      anchor: { x: rect.left, y: rect.top, width: rect.right - rect.left, height: rect.bottom - rect.top },
    };
  }

  function closeNote(): void {
    note = null;
  }

  /** Reloads the shown file's marks (notes, ML lines, call sites) without moving the scroll or the focus. */
  async function refresh(): Promise<void> {
    const path = shownPath;
    if (path === null) return;
    const current = generation;
    try {
      const [loaded, arrowReply] = await Promise.all([loadFile(path), loadFlowArrows(path)]);
      if (current !== generation) return;
      file = loaded;
      arrows = flowArrowsFrom(arrowReply.arrows);
    } catch {
      // The file may be gone or unreadable now; the view keeps what it last showed.
    }
  }

  function dragFlowDivider(event: PointerEvent): void {
    event.preventDefault();
    const handle = event.currentTarget;
    if (!(handle instanceof HTMLElement)) return;
    handle.setPointerCapture(event.pointerId);
    const startY = event.clientY;
    const startHeight = flowHeight;
    const move = (moved: PointerEvent): void => {
      const total = root?.clientHeight ?? 0;
      const wanted = startHeight - (moved.clientY - startY);
      flowHeight = Math.min(Math.max(wanted, MIN_FLOW_HEIGHT), Math.max(MIN_FLOW_HEIGHT, total - MIN_SOURCE_HEIGHT));
    };
    const up = (): void => {
      handle.removeEventListener("pointermove", move);
      handle.removeEventListener("pointerup", up);
    };
    handle.addEventListener("pointermove", move);
    handle.addEventListener("pointerup", up);
  }

  onMount(() => {
    const stops = [
      on("ml.changed", () => void refresh()),
      on("notes.changed", () => void refresh()),
      on("workspace.changed", () => void refresh()),
      on<JobFinished>("job.finished", (job) => {
        if (job.kind === "index" && job.status === "completed") void refresh();
      }),
    ];
    return () => {
      for (const stop of stops) stop();
      window.clearTimeout(typeTimer);
    };
  });
</script>

<div class="viewer" bind:this={root}>
  {#if shownPath === null}
    <div class="empty">Choose a folder, then select a file to view its source.</div>
  {:else if file === null}
    {#if loadError !== null}
      <pre class="unreadable">{loadError}</pre>
    {/if}
  {:else}
    {#if file.mlLines.length > 0}
      <HighlightedLines lines={file.mlLines} onSelect={(line) => code?.scrollToLine(line)} />
    {/if}
    <div class="source">
      {#if findOpen}
        <!-- Escape closes the bar from anywhere in it, as AppKit's search field does. -->
        <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
        <div
          class="find"
          role="search"
          bind:this={findBar}
          onkeydown={(event) => {
            if (event.key === "Escape") clearFind();
          }}
        >
          <SearchField value={findTerm} placeholder="Find in file…" width={240} onInput={setFindTerm} onEnter={advanceMatch} />
          <span class="count">{matchLabel}</span>
        </div>
      {/if}
      <!-- A hover listener only: the code area is the editor's own surface, and the editor takes the clicks. -->
      <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
      <div class="code" role="presentation" bind:this={codeHost} onmousemove={hover}>
        <CodeView
          bind:this={code}
          source={file.text}
          {tokens}
          functions={file.functionRanges}
          classes={file.classRanges}
          callSites={file.callSites}
          {matches}
          focus={focusRange}
          {riskLines}
          {markedLines}
          flowArrows={shownArrows}
          showFlowArrows={arrowsOn}
          onTarget={onTarget}
          onLineClick={openNote}
          onEscape={clearFocus}
          onContextMenu={(info, event) => void openContextMenu(info, event)}
        />
        {#if callers.length > 0}
          <TunnelBar kind="callers" placement="top" items={callers} onPick={pivot} />
        {/if}
        {#if callees.length > 0}
          <TunnelBar kind="callees" placement="bottom" items={callees} onPick={pivot} />
        {/if}
        {#if tooltip}
          <TypeTooltip text={tooltip.text} anchor={tooltip.anchor} onClose={hideTooltip} />
        {/if}
      </div>
    </div>
    {#if flowGraph}
      <div
        class="divider"
        role="separator"
        aria-orientation="horizontal"
        onpointerdown={dragFlowDivider}
      ></div>
      <div class="flow" style="height:{flowHeight}px">
        <div class="flow-title">{flowTitle}</div>
        <div class="flow-body">
          <DataFlowDiagram graph={flowGraph} />
        </div>
      </div>
    {/if}
  {/if}
  {#if note}
    <NotePopover path={note.path} line={note.line} anchor={note.anchor} onClose={closeNote} />
  {/if}
</div>

<style>
  .viewer {
    position: relative;
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
    min-width: 0;
  }
  .empty {
    margin: auto;
    font-size: 15px;
    color: var(--secondary-label);
  }
  .unreadable {
    margin: 0;
    padding: 8px;
    font: 13px var(--font-mono);
    color: var(--system-red);
    white-space: pre-wrap;
  }
  .source {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }
  .find {
    flex: none;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 12px 0;
  }
  .count {
    font-size: 11px;
    color: var(--secondary-label);
    white-space: nowrap;
  }
  .code {
    position: relative;
    flex: 1;
    min-height: 0;
  }
  .divider {
    flex: none;
    height: 6px;
    cursor: row-resize;
    background: linear-gradient(to bottom, transparent 2px, rgba(0, 0, 0, 0.6) 2px, rgba(0, 0, 0, 0.6) 3px, transparent 3px);
  }
  .flow {
    flex: none;
    display: flex;
    flex-direction: column;
    min-height: 0;
    background: var(--control-bg);
  }
  .flow-title {
    flex: none;
    padding: 8px 12px 0;
    font-size: 12px;
    font-weight: 600;
    color: var(--secondary-label);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .flow-body {
    flex: 1;
    min-height: 0;
    margin-top: 6px;
  }
</style>
