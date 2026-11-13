<script lang="ts">
  // The source text view (`ClickableTextView` inside `SourceViewer`): read-only
  // code with a line-number gutter, syntax colours, clickable names, find
  // matches, focus-mode dimming, ML risk backgrounds and the control-flow
  // arrow overlay. It only draws; what to show comes from its props.
  import type { EditorView } from "@codemirror/view";
  import { untrack } from "svelte";
  import { measureText } from "../diagram/measure";
  import { type NamedRange, type TextRange, type TokenRange, buildSegments, gutterWidth, lineStarts } from "./decorations";
  import { type ClickTarget, createCodeEditor, updateCodeEditor } from "./editor";
  import { type FlowArrow, arrowShapes, indentColumns, shapesToSvg } from "./flowArrows";

  let {
    source,
    tokens = [],
    functions = [],
    classes = [],
    callSites = [],
    matches = [],
    focus = null,
    riskLines = {},
    markedLines = [],
    flowArrows = [],
    showFlowArrows = false,
    onTarget,
    onLineClick,
    onEscape,
    onContextMenu,
  }: {
    source: string;
    tokens?: readonly TokenRange[];
    functions?: readonly NamedRange[];
    classes?: readonly NamedRange[];
    callSites?: readonly NamedRange[];
    matches?: readonly TextRange[];
    focus?: TextRange | null;
    riskLines?: Readonly<Record<number, number>>;
    markedLines?: readonly number[];
    flowArrows?: readonly FlowArrow[];
    showFlowArrows?: boolean;
    onTarget?: (target: ClickTarget) => void;
    onLineClick?: (line: number) => void;
    onEscape?: () => void;
    onContextMenu?: (info: { pos: number | null; from: number; to: number }, event: MouseEvent) => void;
  } = $props();

  /** `textContainerOrigin.x`: where the overlay measures a line's code from. */
  const TEXT_ORIGIN_X = 8;

  let host: HTMLDivElement | undefined = $state();
  let view = $state.raw<EditorView>();
  let overlay: SVGSVGElement | undefined;
  let overlayFrame = 0;
  let overlayArrows: readonly FlowArrow[] = [];
  let starts: number[] = [0];

  $effect(() => {
    if (!host) return;
    const created = createCodeEditor(host, untrack(() => source), {
      onTarget: (target) => onTarget?.(target),
      onLineClick: (line) => onLineClick?.(line),
      onEscape: () => onEscape?.(),
      onContextMenu: (info, event) => onContextMenu?.(info, event),
      onLayout: scheduleOverlay,
    });
    overlay = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    overlay.classList.add("karma-flow-overlay");
    created.scrollDOM.append(overlay);
    view = created;
    return () => {
      cancelAnimationFrame(overlayFrame);
      overlayFrame = 0;
      created.destroy();
      view = undefined;
      overlay = undefined;
    };
  });

  $effect(() => {
    if (!view) return;
    starts = lineStarts(source);
    updateCodeEditor(view, {
      source,
      segments: buildSegments({
        source,
        tokens,
        functions,
        classes,
        callSites,
        matches,
        focus,
        riskLines,
      }),
      gutter: { markedLines: new Set(markedLines), riskLines },
      gutterWidth: gutterWidth(source),
    });
  });

  $effect(() => {
    overlayArrows = showFlowArrows ? flowArrows : [];
    if (view) scheduleOverlay();
  });

  function scheduleOverlay() {
    if (overlayFrame === 0) overlayFrame = requestAnimationFrame(drawOverlay);
  }

  /** `drawFlowArrowsOverlay`: arrows are placed from each line's first row, in text view coordinates. */
  function drawOverlay() {
    overlayFrame = 0;
    if (!view || !overlay) return;
    if (overlayArrows.length === 0) {
      overlay.replaceChildren();
      overlay.style.display = "none";
      return;
    }
    const editor = view;
    const content = editor.contentDOM;
    const padding = editor.documentPadding;
    const length = editor.state.doc.length;
    const half = editor.defaultLineHeight / 2;
    const font = `13px ${getComputedStyle(content).fontFamily}`;
    const spaceWidth = measureText(" ", font);
    const text = editor.state.doc;

    overlay.style.display = "";
    overlay.style.left = `${content.offsetLeft}px`;
    overlay.style.top = `${content.offsetTop}px`;
    overlay.setAttribute("width", String(content.offsetWidth));
    overlay.setAttribute("height", String(content.offsetHeight));

    const shapes = arrowShapes(
      overlayArrows,
      (line) => {
        const offset = starts[line - 1];
        if (line < 1 || offset === undefined || offset >= length) return null;
        return editor.lineBlockAt(offset).top + padding.top + half;
      },
      (line) => {
        const start = starts[line - 1];
        if (line < 1 || start === undefined) return TEXT_ORIGIN_X;
        const lineText = text.lineAt(Math.min(start, length)).text;
        return TEXT_ORIGIN_X + indentColumns(lineText) * spaceWidth;
      },
    );
    overlay.innerHTML = shapesToSvg(shapes);
  }

  /** Scrolls so the 1-based `line` is visible and selects it (`SourceViewer.scrollToLine`). */
  export function scrollToLine(line: number) {
    if (!view) return;
    const doc = view.state.doc;
    const target = doc.line(Math.min(Math.max(line, 1), doc.lines));
    if (target.length === 0) return;
    view.dispatch({
      selection: { anchor: target.from, head: target.to },
      scrollIntoView: true,
    });
  }

  /** Selects and scrolls to a UTF-16 range (find matches, search results). */
  export function revealRange(location: number, length: number) {
    if (!view) return;
    const max = view.state.doc.length;
    const from = Math.min(Math.max(location, 0), max);
    const to = Math.min(from + Math.max(length, 0), max);
    view.dispatch({ selection: { anchor: from, head: to }, scrollIntoView: true });
  }

  export function focusEditor() {
    view?.focus();
  }
</script>

<div class="code-view selectable" bind:this={host}></div>

<style>
  .code-view {
    height: 100%;
    min-height: 0;
    min-width: 0;
    position: relative;
  }
  .code-view :global(.cm-editor) {
    height: 100%;
  }
  .code-view :global(.tok-keyword) {
    color: var(--tok-keyword);
  }
  .code-view :global(.tok-string) {
    color: var(--tok-string);
  }
  .code-view :global(.tok-comment) {
    color: var(--tok-comment);
  }
  .code-view :global(.tok-number) {
    color: var(--tok-number);
  }
  .code-view :global(.tok-type) {
    color: var(--tok-type);
  }
  .code-view :global(.cm-link-function),
  .code-view :global(.cm-link-class),
  .code-view :global(.cm-link-call) {
    text-decoration: underline;
    cursor: pointer;
  }
  .code-view :global(.cm-link-function) {
    color: var(--accent);
  }
  .code-view :global(.cm-link-class) {
    color: var(--system-purple);
  }
  .code-view :global(.cm-link-call) {
    color: rgb(0, 140, 128);
  }
  .code-view :global(.karma-flow-overlay) {
    position: absolute;
    pointer-events: none;
    overflow: visible;
    z-index: 3;
  }
</style>
