// CodeMirror 6 set up as the read-only equivalent of the AppKit source text
// view (`ClickableTextView` plus `LineNumberRulerView`).
//
// `EditorState.lineSeparator` is "\n" so a "\r" stays an ordinary character in
// the text, and positions are UTF-16 offsets exactly as the server's.
import { EditorState, RangeSetBuilder, StateEffect, StateField } from "@codemirror/state";
import { Decoration, type DecorationSet, EditorView, GutterMarker, drawSelection, gutter } from "@codemirror/view";
import { type LinkKind, type Segment, riskBarOpacity } from "./decorations";

export interface GutterData {
  /** Lines that carry a saved note (a dot and the accent colour). */
  markedLines: ReadonlySet<number>;
  /** 1-based line → ML probability (a red bar and red number). */
  riskLines: Readonly<Record<number, number>>;
}

export interface ClickTarget {
  kind: LinkKind;
  name: string;
  /** UTF-16 offset under the pointer. */
  pos: number;
}

export interface EditorCallbacks {
  /** A clickable function, class or call-site name was clicked. */
  onTarget(target: ClickTarget): void;
  /** A line number in the gutter was clicked (1-based). */
  onLineClick(line: number): void;
  /** Escape was pressed in the text; answers whether the viewer used it. */
  onEscape(): boolean;
  /** Right-click: the offset under the pointer and the current selection. */
  onContextMenu(info: { pos: number | null; from: number; to: number }, event: MouseEvent): void;
  /** The text or its layout changed (lines moved or re-wrapped); overlays drawn over the text must be redrawn. */
  onLayout(): void;
}

const setDecorations = StateEffect.define<DecorationSet>();
const setGutterData = StateEffect.define<GutterData>();

const decorationField = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(value, transaction) {
    for (const effect of transaction.effects) if (effect.is(setDecorations)) return effect.value;
    return value.map(transaction.changes);
  },
  provide: (field) => EditorView.decorations.from(field),
});

const gutterField = StateField.define<GutterData>({
  create: () => ({ markedLines: new Set(), riskLines: {} }),
  update(value, transaction) {
    for (const effect of transaction.effects) if (effect.is(setGutterData)) return effect.value;
    return value;
  },
});

class LineNumberMarker extends GutterMarker {
  constructor(
    readonly line: number,
    readonly marked: boolean,
    readonly risk: number | undefined,
  ) {
    super();
  }

  eq(other: LineNumberMarker): boolean {
    return other.line === this.line && other.marked === this.marked && other.risk === this.risk;
  }

  toDOM(): HTMLElement {
    const element = document.createElement("div");
    element.className = "karma-line-number";
    element.textContent = String(this.line);
    if (this.marked) {
      element.classList.add("marked");
      const dot = document.createElement("span");
      dot.className = "karma-note-dot";
      element.append(dot);
    }
    if (this.risk !== undefined) {
      element.classList.add("risky");
      const bar = document.createElement("span");
      bar.className = "karma-risk-bar";
      bar.style.backgroundColor = `rgba(255, 69, 58, ${riskBarOpacity(this.risk)})`;
      element.append(bar);
    }
    return element;
  }
}

const theme = EditorView.theme(
  {
    "&": { height: "100%", backgroundColor: "var(--text-bg)", color: "var(--label)", fontSize: "13px" },
    "&.cm-focused": { outline: "none" },
    ".cm-scroller": { fontFamily: "var(--font-mono)", lineHeight: "16px", position: "relative", overflow: "auto" },
    ".cm-content": { padding: "4px 0", caretColor: "transparent", tabSize: "4", userSelect: "text" },
    ".cm-line": { padding: "0 8px 0 13px" },
    ".cm-cursor": { display: "none !important" },
    ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": { backgroundColor: "var(--selection) !important" },
    ".cm-gutters": {
      backgroundColor: "#282828",
      color: "var(--secondary-label)",
      border: "none",
      userSelect: "none",
    },
    ".cm-gutter.karma-gutter": { width: "var(--gutter-width, 36px)" },
    ".cm-gutter.karma-gutter .cm-gutterElement": { padding: "0", cursor: "pointer" },
    ".karma-line-number": {
      position: "relative",
      textAlign: "right",
      paddingRight: "6px",
      fontSize: "11px",
      fontVariantNumeric: "tabular-nums",
      color: "var(--secondary-label)",
    },
    ".karma-line-number.marked": { color: "var(--accent)" },
    ".karma-line-number.risky": { color: "var(--system-red)" },
    ".karma-note-dot": {
      position: "absolute",
      left: "2px",
      top: "calc(50% - 3px)",
      width: "6px",
      height: "6px",
      borderRadius: "50%",
      backgroundColor: "var(--accent)",
    },
    ".karma-risk-bar": { position: "absolute", left: "0", top: "-1px", width: "3px", height: "100%" },
  },
  { dark: true },
);

/** Creates the viewer inside `parent` with `source` as its text. */
export function createCodeEditor(parent: HTMLElement, source: string, callbacks: EditorCallbacks): EditorView {
  const state = EditorState.create({
    doc: source,
    extensions: [
      EditorState.lineSeparator.of("\n"),
      EditorState.readOnly.of(true),
      EditorView.lineWrapping,
      drawSelection(),
      decorationField,
      gutterField,
      gutter({
        class: "karma-gutter",
        lineMarker(view, line) {
          const number = view.state.doc.lineAt(line.from).number;
          const data = view.state.field(gutterField);
          return new LineNumberMarker(number, data.markedLines.has(number), data.riskLines[number]);
        },
        lineMarkerChange: (update) =>
          update.transactions.some((transaction) => transaction.effects.some((effect) => effect.is(setGutterData))),
        domEventHandlers: {
          mousedown(view, line) {
            callbacks.onLineClick(view.state.doc.lineAt(line.from).number);
            return true;
          },
        },
      }),
      EditorView.domEventHandlers({
        mousedown(event, view) {
          if (event.button !== 0 || !(event.target instanceof Element)) return false;
          const link = event.target.closest<HTMLElement>("[data-link-kind]");
          if (!link) return false;
          const pos = view.posAtCoords({ x: event.clientX, y: event.clientY }, false);
          callbacks.onTarget({
            kind: link.dataset.linkKind as LinkKind,
            name: link.dataset.linkName ?? "",
            pos,
          });
          event.preventDefault();
          return true;
        },
        keydown(event) {
          if (event.key !== "Escape") return false;
          // Only an Escape the viewer used (leaving focus mode) is consumed; any other reaches the window, which
          // closes on it (the definition window).
          return callbacks.onEscape();
        },
        contextmenu(event, view) {
          const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
          const selection = view.state.selection.main;
          callbacks.onContextMenu({ pos, from: selection.from, to: selection.to }, event);
          return true;
        },
      }),
      EditorView.updateListener.of((update) => {
        if (update.docChanged || update.viewportChanged || update.geometryChanged) callbacks.onLayout();
      }),
      theme,
    ],
  });
  return new EditorView({ state, parent });
}

function decorationsFor(segments: readonly Segment[]): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  for (const segment of segments) {
    const attributes: Record<string, string> = {};
    if (segment.style !== "") attributes.style = segment.style;
    if (segment.link) {
      attributes["data-link-kind"] = segment.link.kind;
      attributes["data-link-name"] = segment.link.name;
    }
    builder.add(segment.from, segment.to, Decoration.mark({ class: segment.className, attributes }));
  }
  return builder.finish();
}

export interface EditorContent {
  source: string;
  segments: readonly Segment[];
  gutter: GutterData;
  gutterWidth: number;
}

/** Replaces the text when it changed and applies the new highlights and gutter, in one transaction. */
export function updateCodeEditor(view: EditorView, content: EditorContent): void {
  const current = view.state.doc.toString();
  view.dom.style.setProperty("--gutter-width", `${content.gutterWidth}px`);
  view.dispatch({
    changes: current === content.source ? undefined : { from: 0, to: current.length, insert: content.source },
    effects: [
      setDecorations.of(decorationsFor(content.segments)),
      setGutterData.of(content.gutter),
      // A different file opens at its top, like `scrollToBeginningOfDocument`.
      ...(current === content.source ? [] : [EditorView.scrollIntoView(0, { y: "start" })]),
    ],
  });
}
