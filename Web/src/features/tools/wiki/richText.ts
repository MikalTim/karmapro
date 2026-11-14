// The wiki page as the editor works on it: one flat list of styled pieces where
// a paragraph break is a piece of its own ("\n"). Offsets count UTF-16 units,
// which is what the browser's selection and the server's text positions use,
// so a caret position is an index into the flattened text.
//
// The shapes mirror `WikiDocument` (Sources/KarmaCore/tools/WikiRTF.swift). The
// one addition is `dim`: the bracket colour `[[links]]` get in the editor. It is
// shown but never saved, because AppKit derives it again from the text.

export interface WikiRun {
  text: string;
  bold: boolean;
  italic: boolean;
  underline: boolean;
  code: boolean;
  heading: boolean;
  link?: string;
}

export interface WikiParagraph {
  runs: WikiRun[];
}

export interface WikiDocument {
  paragraphs: WikiParagraph[];
}

export interface TextStyle {
  bold: boolean;
  italic: boolean;
  underline: boolean;
  code: boolean;
  heading: boolean;
  link: string | null;
  dim: boolean;
}

export interface Piece {
  text: string;
  style: TextStyle;
}

/** The toolbar's formatting actions (`BoldClicked` … `bodyClicked`). */
export type FormatOp = "bold" | "italic" | "underline" | "code" | "heading" | "body";

/** Typing attributes chosen with a collapsed caret, applied to the next typed text. */
export interface PendingStyle {
  offset: number;
  style: TextStyle;
}

export const NEWLINE = "\n";
export const WIKI_LINK_PREFIX = "wiki://page/";

export const DEFAULT_STYLE: TextStyle = {
  bold: false,
  italic: false,
  underline: false,
  code: false,
  heading: false,
  link: null,
  dim: false,
};

export const NEWLINE_PIECE: Piece = { text: NEWLINE, style: DEFAULT_STYLE };

export function sameStyle(a: TextStyle, b: TextStyle): boolean {
  return (
    a.bold === b.bold &&
    a.italic === b.italic &&
    a.underline === b.underline &&
    a.code === b.code &&
    a.heading === b.heading &&
    a.link === b.link &&
    a.dim === b.dim
  );
}

// MARK: - Document conversion

export function fromDocument(document: WikiDocument): Piece[] {
  const pieces: Piece[] = [];
  document.paragraphs.forEach((paragraph, index) => {
    if (index > 0) pieces.push(NEWLINE_PIECE);
    for (const run of paragraph.runs) {
      pieces.push({
        text: run.text,
        style: {
          bold: run.bold,
          italic: run.italic,
          underline: run.underline,
          code: run.code,
          heading: run.heading,
          link: run.link ?? null,
          dim: false,
        },
      });
    }
  });
  return normalize(pieces);
}

/** The document the pieces stand for. An empty text is no paragraphs, as `WikiDocument(plain: "")` is. */
export function toDocument(pieces: Piece[]): WikiDocument {
  const normal = normalize(pieces);
  if (normal.length === 0) return { paragraphs: [] };
  const paragraphs: WikiParagraph[] = [];
  let runs: WikiRun[] = [];
  for (const piece of normal) {
    if (piece.text === NEWLINE) {
      paragraphs.push({ runs });
      runs = [];
    } else {
      runs.push(toRun(piece));
    }
  }
  paragraphs.push({ runs });
  return { paragraphs };
}

function toRun(piece: Piece): WikiRun {
  const { style } = piece;
  const run: WikiRun = {
    text: piece.text,
    bold: style.bold,
    italic: style.italic,
    underline: style.underline,
    code: style.code,
    heading: style.heading,
  };
  if (style.link !== null) run.link = style.link;
  return run;
}

// MARK: - Pieces

export function flatten(pieces: Piece[]): string {
  let text = "";
  for (const piece of pieces) text += piece.text;
  return text;
}

/** Pieces of `text` in one style, with a paragraph piece for each `\n`. */
export function textToPieces(text: string, style: TextStyle): Piece[] {
  const pieces: Piece[] = [];
  text.split(NEWLINE).forEach((part, index) => {
    if (index > 0) pieces.push(NEWLINE_PIECE);
    if (part.length > 0) pieces.push({ text: part, style });
  });
  return pieces;
}

/** Drops empty pieces and joins neighbours of the same style. Paragraph pieces never merge. */
export function normalize(pieces: Piece[]): Piece[] {
  const out: Piece[] = [];
  for (const piece of pieces) {
    if (piece.text.length === 0) continue;
    const last = out[out.length - 1];
    if (last && piece.text !== NEWLINE && last.text !== NEWLINE && sameStyle(last.style, piece.style)) {
      out[out.length - 1] = { text: last.text + piece.text, style: last.style };
    } else {
      out.push(piece);
    }
  }
  return out;
}

/** The same pieces with a piece boundary at `at` (no-op at a paragraph break or at an existing boundary). */
export function splitAt(pieces: Piece[], at: number): Piece[] {
  const out: Piece[] = [];
  let offset = 0;
  for (const piece of pieces) {
    const end = offset + piece.text.length;
    if (at > offset && at < end && piece.text !== NEWLINE) {
      const cut = at - offset;
      out.push({ text: piece.text.slice(0, cut), style: piece.style });
      out.push({ text: piece.text.slice(cut), style: piece.style });
    } else {
      out.push(piece);
    }
    offset = end;
  }
  return out;
}

/** Applies `change` to the style of every text piece inside [start, end). Paragraph breaks keep their style. */
export function mapRange(pieces: Piece[], start: number, end: number, change: (style: TextStyle) => TextStyle): Piece[] {
  const split = splitAt(splitAt(pieces, start), end);
  let offset = 0;
  const out = split.map((piece) => {
    const from = offset;
    offset += piece.text.length;
    if (piece.text === NEWLINE || from < start || offset > end) return piece;
    return { text: piece.text, style: change(piece.style) };
  });
  return normalize(out);
}

/** Replaces [start, end) with `text` in `style`. Returns the pieces and the caret after the new text. */
export function replaceRange(
  pieces: Piece[],
  start: number,
  end: number,
  text: string,
  style: TextStyle,
): { pieces: Piece[]; caret: number } {
  const split = splitAt(splitAt(pieces, start), end);
  const before: Piece[] = [];
  const after: Piece[] = [];
  let offset = 0;
  for (const piece of split) {
    const from = offset;
    offset += piece.text.length;
    if (offset <= start) before.push(piece);
    else if (from >= end) after.push(piece);
  }
  return {
    pieces: normalize([...before, ...textToPieces(text, style), ...after]),
    caret: start + text.length,
  };
}

/** The style of the text character at `offset`, or null at a paragraph break or past the end. */
export function styleAt(pieces: Piece[], offset: number): TextStyle | null {
  let from = 0;
  for (const piece of pieces) {
    const to = from + piece.text.length;
    if (offset >= from && offset < to) return piece.text === NEWLINE ? null : piece.style;
    from = to;
  }
  return null;
}

/** The style of the character before `offset`, the style AppKit's typing attributes follow. */
export function styleBefore(pieces: Piece[], offset: number): TextStyle | null {
  return offset > 0 ? styleAt(pieces, offset - 1) : null;
}

/** The style new text gets at a caret: a pending choice when one is set here, else the character before the caret. */
export function typingStyle(pieces: Piece[], offset: number, pending: PendingStyle | null): TextStyle {
  if (pending && pending.offset === offset) return pending.style;
  return styleBefore(pieces, offset) ?? styleAt(pieces, offset) ?? DEFAULT_STYLE;
}

// MARK: - Formatting

/**
 * The style after one toolbar action. Bold and italic flip on their own;
 * underline takes `underlineOn`; code, heading and body replace the font the way
 * `NSFont` replaces it (code keeps the size, heading is 20 pt bold, body 14 pt regular).
 */
export function formatStyle(style: TextStyle, op: FormatOp, underlineOn: boolean): TextStyle {
  switch (op) {
    case "bold":
      return { ...style, bold: !style.bold };
    case "italic":
      return { ...style, italic: !style.italic };
    case "underline":
      return { ...style, underline: underlineOn };
    case "code":
      return { ...style, code: true, bold: false, italic: false };
    case "heading":
      return { ...style, heading: true, bold: true, italic: false, code: false };
    case "body":
      return { ...style, heading: false, bold: false, italic: false, code: false };
  }
}

/** The style a collapsed caret gets after one toolbar action (`typingAttributes` update). */
export function caretStyleAfter(base: TextStyle, op: FormatOp): TextStyle {
  return formatStyle(base, op, !base.underline);
}

/**
 * Applies a toolbar action to a selection. Bold and italic flip per run; underline
 * is decided by the first character and applied to the whole selection.
 */
export function applyFormat(pieces: Piece[], start: number, end: number, op: FormatOp): Piece[] {
  const underlineOn = !(styleAt(pieces, start) ?? DEFAULT_STYLE).underline;
  return mapRange(pieces, start, end, (style) => formatStyle(style, op, underlineOn));
}

/** The style of inserted link text: the base font, underlined, with the target. */
export function linkStyle(base: TextStyle, url: string): TextStyle {
  return { ...base, link: url, underline: true, dim: false };
}

// MARK: - Links

const PATH_SAFE = /^[A-Za-z0-9\-._~!$&'()*+,;=:@/]$/;

/** The `wiki://page/<name>` link for a page name (`wikiURL(for:)`: the URL path character set). */
export function wikiLinkURL(target: string): string {
  let encoded = "";
  for (const character of target) {
    encoded += PATH_SAFE.test(character) ? character : encodeURIComponent(character);
  }
  return WIKI_LINK_PREFIX + encoded;
}

export function isWikiLink(href: string): boolean {
  return /^wiki:/i.test(href);
}

/**
 * The page name a `wiki://` link points at: the last path component, percent-decoded
 * (`navigate(to:)`). Null for other links, and for a link without a name.
 */
export function linkTarget(href: string): string | null {
  if (!isWikiLink(href)) return null;
  const path = href.replace(/^wiki:(\/\/[^/]*)?/i, "").replace(/\/+$/, "");
  const last = path.slice(path.lastIndexOf("/") + 1);
  let decoded: string;
  try {
    decoded = decodeURIComponent(last);
  } catch {
    return null;
  }
  return decoded === "" ? null : decoded;
}

const LINK_PATTERN = "\\[\\[([^\\[\\]]+)\\]\\]";

/**
 * Styles every `[[Page Name]]` as a link (`applyWikiLinks`): the inner text takes the
 * link (its font follows the first character) and both bracket pairs are dimmed.
 * Like AppKit, it adds styling and never removes it.
 */
export function applyWikiLinks(pieces: Piece[]): Piece[] {
  const text = flatten(pieces);
  const pattern = new RegExp(LINK_PATTERN, "g");
  let next = pieces;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text)) !== null) {
    const start = match.index;
    const innerStart = start + 2;
    const innerEnd = start + match[0].length - 2;
    const url = wikiLinkURL(match[1]);
    const existing = styleAt(next, innerStart)?.link ?? null;
    if (existing !== url) {
      const first = styleAt(next, innerStart) ?? DEFAULT_STYLE;
      next = mapRange(next, innerStart, innerEnd, (style) => ({
        ...style,
        bold: first.bold,
        italic: first.italic,
        code: first.code,
        heading: first.heading,
        link: url,
      }));
    }
    next = mapRange(next, start, innerStart, (style) => ({ ...style, dim: true }));
    next = mapRange(next, innerEnd, innerEnd + 2, (style) => ({ ...style, dim: true }));
  }
  return next;
}

// MARK: - Comparison and counting

export function samePieces(a: Piece[], b: Piece[]): boolean {
  return a.length === b.length && a.every((piece, index) => piece.text === b[index].text && sameStyle(piece.style, b[index].style));
}

/** The number of user-perceived characters, as `NSString`'s `String.count` in the status line. */
export function characterCount(text: string): number {
  return Array.from(new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text)).length;
}
