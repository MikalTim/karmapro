// The DOM half of the page editor. It draws the styled pieces into the editable root
// and maps between DOM points and flattened text offsets. The rest of the page logic
// is pure (`richText.ts`, `editorModel.ts`).
import { NEWLINE, type Piece } from "../richText";
import { styleClasses, type Span } from "./editorModel";

interface DomPoint {
  node: Node;
  offset: number;
}

/**
 * Draws the pieces as one block per paragraph, a span (or a link) per piece. An empty
 * paragraph keeps a `<br>` so that it keeps its line height.
 */
export function renderPieces(root: HTMLElement, pieces: Piece[]): void {
  let current: Piece[] = [];
  const paragraphs: Piece[][] = [current];
  for (const piece of pieces) {
    if (piece.text === NEWLINE) {
      current = [];
      paragraphs.push(current);
    } else {
      current.push(piece);
    }
  }
  root.replaceChildren(...paragraphs.map(renderParagraph));
}

function renderParagraph(pieces: Piece[]): HTMLDivElement {
  const paragraph = document.createElement("div");
  if (pieces.length === 0) paragraph.appendChild(document.createElement("br"));
  for (const piece of pieces) paragraph.appendChild(renderPiece(piece));
  return paragraph;
}

function renderPiece(piece: Piece): HTMLElement {
  const { style } = piece;
  // Links carry their target in a data attribute, not in `href`: a link with an href
  // would let the browser navigate on its own (middle click, drag) to a wiki:// address.
  const element = document.createElement(style.link === null ? "span" : "a");
  if (style.link !== null) element.dataset.link = style.link;
  element.className = styleClasses(style).join(" ");
  element.textContent = piece.text;
  return element;
}

/** The selection in flattened offsets, or null when it is not inside `root`. */
export function selectionSpan(root: HTMLElement): Span | null {
  const selection = window.getSelection();
  const anchor = selection?.anchorNode ?? null;
  const focus = selection?.focusNode ?? null;
  if (!selection || !anchor || !focus || !root.contains(anchor) || !root.contains(focus)) return null;
  const from = offsetAt(root, anchor, selection.anchorOffset);
  const to = offsetAt(root, focus, selection.focusOffset);
  return { start: Math.min(from, to), end: Math.max(from, to) };
}

/** Puts the browser selection on the flattened span. */
export function selectSpan(root: HTMLElement, span: Span): void {
  const selection = window.getSelection();
  if (!selection) return;
  const start = pointAt(root, span.start);
  const end = pointAt(root, span.end);
  selection.setBaseAndExtent(start.node, start.offset, end.node, end.offset);
}

/** The root's text as `flatten` sees it: one line per child block. */
export function readFlatText(root: HTMLElement): string {
  return Array.from(root.childNodes, (block) => block.textContent ?? "").join(NEWLINE);
}

/**
 * The flattened offset of a DOM point. Every block after the first starts with the
 * "\n" that separates it from the block before, so each block whose start lies before
 * the point adds one.
 */
function offsetAt(root: HTMLElement, node: Node, offset: number): number {
  const range = document.createRange();
  range.setStart(root, 0);
  range.setEnd(node, offset);
  let breaks = 0;
  root.childNodes.forEach((block, index) => {
    if (index > 0 && range.comparePoint(block, 0) === 0) breaks++;
  });
  return range.toString().length + breaks;
}

/** The DOM point at a flattened offset. A break offset falls at the end of the block before it. */
function pointAt(root: HTMLElement, offset: number): DomPoint {
  const blocks = Array.from(root.childNodes);
  let blockStart = 0;
  for (let index = 0; index < blocks.length; index++) {
    if (index > 0) blockStart += 1;
    const block = blocks[index];
    const length = block.textContent?.length ?? 0;
    if (offset <= blockStart + length || index === blocks.length - 1) {
      return pointInBlock(block, offset - blockStart);
    }
    blockStart += length;
  }
  return { node: root, offset: 0 };
}

function pointInBlock(block: ChildNode, within: number): DomPoint {
  if (block.nodeType === Node.TEXT_NODE) {
    return { node: block, offset: Math.min(within, block.textContent?.length ?? 0) };
  }
  const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
  let remaining = within;
  for (let text = walker.nextNode(); text; text = walker.nextNode()) {
    const length = text.textContent?.length ?? 0;
    if (remaining <= length) return { node: text, offset: remaining };
    remaining -= length;
  }
  return { node: block, offset: 0 };
}
