<script lang="ts">
  // The page body (AppKit's WikiLinkTextView). The styled text lives in `pieces` and
  // the DOM is drawn from it after every change. Edits the browser would make by
  // itself (typing, Enter, Backspace, paste, undo) are taken over in `beforeinput`, so
  // the style comes from the model and not from wherever the browser put the text.
  // Edits that cannot be intercepted (IME composition) are read back from the DOM on
  // `input`.
  import { onMount } from "svelte";
  import {
    applyFormat,
    applyWikiLinks,
    caretStyleAfter,
    DEFAULT_STYLE,
    flatten,
    linkStyle,
    linkTarget,
    replaceRange,
    samePieces,
    typingStyle,
    type FormatOp,
    type Piece,
    type PendingStyle,
  } from "../richText";
  import {
    deletionRange,
    diffText,
    externalHref,
    normalizePastedText,
    type DeleteDirection,
    type DeleteUnit,
    type Span,
  } from "./editorModel";
  import { readFlatText, renderPieces, selectionSpan, selectSpan } from "./richTextDom";

  let {
    initial,
    onChange,
    onOpenLink,
  }: {
    initial: Piece[];
    onChange?: (pieces: Piece[]) => void;
    /** Called with the page name of a wiki link that was clicked. */
    onOpenLink?: (target: string) => void;
  } = $props();

  // Undo steps are capped so a long editing session cannot grow the history without bound.
  const HISTORY_LIMIT = 100;

  interface HistoryEntry {
    pieces: Piece[];
    span: Span;
  }

  let root: HTMLDivElement | undefined;
  let pieces: Piece[] = [];
  let pending: PendingStyle | null = null;
  let lastSpan: Span = { start: 0, end: 0 };
  // The caret a typing edit left. A typed character that starts there joins the undo step of the run before it.
  let expectedCaret = -1;
  let typingRun = false;
  const undoStack: HistoryEntry[] = [];
  const redoStack: HistoryEntry[] = [];

  onMount(() => {
    const element = root;
    if (!element) return undefined;
    pieces = initial;
    element.focus();
    renderPieces(element, pieces);
    selectSpan(element, { start: 0, end: 0 });
    lastSpan = { start: 0, end: 0 };
    // Mouse only, as in AppKit: a link is followed by a click, not from the keyboard.
    element.addEventListener("click", onClick);
    return () => element.removeEventListener("click", onClick);
  });

  /** The selection now. While it is outside the editor, the last one seen inside it. */
  function currentSpan(): Span {
    const span = root ? selectionSpan(root) : null;
    if (span) lastSpan = span;
    return lastSpan;
  }

  /**
   * Makes `next` the page: applies the wiki link styling, draws it, puts the caret back
   * at `span` and records an undo step. A run of typed characters shares one step.
   */
  function commit(next: Piece[], span: Span, typing: boolean): void {
    if (!root) return;
    const before = currentSpan();
    const continues = typing && typingRun && before.start === before.end && before.start === expectedCaret;
    if (!continues) undoStack.push({ pieces, span: before });
    if (undoStack.length > HISTORY_LIMIT) undoStack.shift();
    redoStack.length = 0;
    typingRun = typing;
    pending = null;
    pieces = applyWikiLinks(next);
    expectedCaret = span.end;
    root.focus();
    renderPieces(root, pieces);
    selectSpan(root, span);
    lastSpan = span;
    onChange?.(pieces);
  }

  /** Undo or redo: moves one step along `from` and records the page it leaves on `to`. */
  function restore(from: HistoryEntry[], to: HistoryEntry[]): void {
    const entry = from.pop();
    if (!entry || !root) return;
    to.push({ pieces, span: currentSpan() });
    pieces = entry.pieces;
    pending = null;
    typingRun = false;
    expectedCaret = -1;
    root.focus();
    renderPieces(root, pieces);
    selectSpan(root, entry.span);
    lastSpan = entry.span;
    onChange?.(pieces);
  }

  /** Replaces the span with `text`, in the style typed there: the toolbar choice at a caret, else the text before it. */
  function replace(event: InputEvent, span: Span, text: string, typing: boolean): void {
    event.preventDefault();
    const collapsed = span.start === span.end;
    const style = typingStyle(pieces, span.start, collapsed ? pending : null);
    const result = replaceRange(pieces, span.start, span.end, text, style);
    commit(result.pieces, { start: result.caret, end: result.caret }, typing && collapsed);
  }

  function remove(event: InputEvent, span: Span, direction: DeleteDirection, unit: DeleteUnit): void {
    event.preventDefault();
    const range = deletionRange(flatten(pieces), span, direction, unit);
    if (range.start === range.end) return;
    const result = replaceRange(pieces, range.start, range.end, "", DEFAULT_STYLE);
    commit(result.pieces, { start: range.start, end: range.start }, span.start === span.end);
  }

  function onBeforeInput(event: InputEvent): void {
    const span = currentSpan();
    switch (event.inputType) {
      case "insertText":
        if (event.data !== null) replace(event, span, event.data, true);
        return;
      case "insertFromPaste":
      case "insertFromDrop": {
        // Only the plain text of a paste is kept; formatting from other sources is not.
        const text = normalizePastedText(event.dataTransfer?.getData("text/plain") || event.data || "");
        if (text === "") event.preventDefault();
        else replace(event, span, text, false);
        return;
      }
      case "insertParagraph":
      case "insertLineBreak":
        replace(event, span, "\n", false);
        return;
      case "deleteContentBackward":
        remove(event, span, "backward", "character");
        return;
      case "deleteContentForward":
        remove(event, span, "forward", "character");
        return;
      case "deleteWordBackward":
        remove(event, span, "backward", "word");
        return;
      case "deleteWordForward":
        remove(event, span, "forward", "word");
        return;
      case "deleteByCut":
      case "deleteByDrag":
        remove(event, span, "backward", "character");
        return;
      case "historyUndo":
        event.preventDefault();
        restore(undoStack, redoStack);
        return;
      case "historyRedo":
        event.preventDefault();
        restore(redoStack, undoStack);
        return;
    }
  }

  /** Reads back an edit made without `beforeinput`, such as an IME composition, and records it as one step. */
  function reconcile(): void {
    if (!root) return;
    const span = currentSpan();
    const edit = diffText(flatten(pieces), readFlatText(root));
    if (!edit) {
      renderPieces(root, pieces);
      selectSpan(root, span);
      return;
    }
    const style = typingStyle(pieces, edit.start, pending);
    const result = replaceRange(pieces, edit.start, edit.oldEnd, edit.inserted, style);
    commit(result.pieces, span, false);
  }

  function onInput(event: Event): void {
    // While an IME composition is open the text is still changing; it is read back once committed.
    if (event instanceof InputEvent && event.isComposing) return;
    reconcile();
  }

  function onClick(event: MouseEvent): void {
    const { target } = event;
    if (!(target instanceof Element)) return;
    const href = target.closest("a")?.dataset.link;
    if (href === undefined) return;
    const page = linkTarget(href);
    if (page !== null) {
      event.preventDefault();
      onOpenLink?.(page);
      return;
    }
    const external = externalHref(href);
    if (external !== null) {
      event.preventDefault();
      window.open(external, "_blank", "noopener");
    }
  }

  function onSelectionChange(): void {
    const span = root ? selectionSpan(root) : null;
    if (!span) return;
    lastSpan = span;
    // A caret that moves away from the toolbar choice drops the choice, as AppKit's typing attributes do.
    if (pending !== null && (span.start !== span.end || span.start !== pending.offset)) pending = null;
  }

  /** A toolbar style: applied to the selection, or chosen for the text typed at a collapsed caret. */
  export function format(op: FormatOp): void {
    const span = currentSpan();
    if (span.end > span.start) {
      const next = applyFormat(pieces, span.start, span.end, op);
      if (!samePieces(next, pieces)) commit(next, span, false);
      return;
    }
    pending = { offset: span.start, style: caretStyleAfter(typingStyle(pieces, span.start, pending), op) };
  }

  export function getContent(): Piece[] {
    return pieces;
  }

  export function selection(): Span {
    return currentSpan();
  }

  export function selectedText(): string {
    const span = currentSpan();
    return flatten(pieces).slice(span.start, span.end);
  }

  /** Replaces `span` with `text` linked to `url` (`insertLink(url:display:at:)`). */
  export function insertLink(span: Span, text: string, url: string): void {
    const style = linkStyle(typingStyle(pieces, span.start, span.start === span.end ? pending : null), url);
    const result = replaceRange(pieces, span.start, span.end, text, style);
    commit(result.pieces, { start: result.caret, end: result.caret }, false);
  }
</script>

<div
  class="wiki-editor"
  contenteditable="true"
  tabindex="0"
  aria-multiline="true"
  role="textbox"
  bind:this={root}
  onbeforeinput={onBeforeInput}
  oninput={onInput}
  oncompositionend={reconcile}
></div>

<svelte:document onselectionchange={onSelectionChange} />

<style>
  /* The page is white with black text, as AppKit's text view is (`textView.backgroundColor = .white`). */
  .wiki-editor {
    box-sizing: border-box;
    min-height: 100%;
    padding: 12px;
    background: #ffffff;
    color: #000000;
    font: 14px/1.35 var(--font-ui);
    white-space: pre-wrap;
    overflow-wrap: break-word;
    outline: none;
  }

  .wiki-editor::selection {
    background: var(--selection);
  }

  .wiki-editor :global(.wiki-bold) {
    font-weight: 700;
  }

  .wiki-editor :global(.wiki-italic) {
    font-style: italic;
  }

  .wiki-editor :global(.wiki-underline) {
    text-decoration: underline;
  }

  .wiki-editor :global(.wiki-code) {
    font-family: var(--font-mono);
  }

  .wiki-editor :global(.wiki-heading) {
    font-size: 20px;
  }

  /* The brackets of [[links]]. Dimmed by opacity: the theme's tertiary label is nearly white, which vanishes on the white page. */
  .wiki-editor :global(.wiki-dim) {
    opacity: 0.4;
  }

  .wiki-editor :global(.wiki-link) {
    color: var(--link);
    text-decoration: underline;
    cursor: pointer;
  }
</style>
