// What the AppKit source viewer stacks onto its text storage, worked out as
// plain data so it can be tested without a browser:
//
// - syntax colours (`SyntaxHighlighter`),
// - clickable function, class and call-site names (`applyClickableLinks`,
//   `applyCallSiteLinks`): underlined and coloured, drawn over the syntax colour,
// - background stack (`refreshTextHighlights`): ML risk lines, then the focus
//   dim over them, then find matches over both.
//
// All offsets are UTF-16 code unit offsets, which are the server's `NSRange`
// units and the same units CodeMirror uses.

export type SyntaxTokenKind = "comment" | "string" | "number" | "keyword" | "type" | "plain";

export interface TextRange {
  location: number;
  length: number;
}

export interface NamedRange extends TextRange {
  name: string;
}

export interface TokenRange extends TextRange {
  kind: SyntaxTokenKind;
}

export type LinkKind = "function" | "class" | "call";

export interface HighlightInput {
  source: string;
  tokens: readonly TokenRange[];
  functions: readonly NamedRange[];
  classes: readonly NamedRange[];
  callSites: readonly NamedRange[];
  /** Find matches (`searchIndicatorColor` background). */
  matches: readonly TextRange[];
  /** The range that stays sharp under focus mode; everything else is dimmed. */
  focus: TextRange | null;
  /** 1-based line → probability (0...1) from the ML scan. */
  riskLines: Readonly<Record<number, number>>;
}

/** One run of text that shares a single set of styles. Runs never overlap. */
export interface Segment {
  from: number;
  to: number;
  className: string;
  /** Inline CSS (the background), or "". */
  style: string;
  /** Set when the run is a clickable name. */
  link?: { kind: LinkKind; name: string };
}

const SEARCH_BACKGROUND = "rgba(255, 230, 77, 0.6)";
const DIM_BACKGROUND = "rgba(0, 0, 0, 0.55)";

/** `systemYellow` → `systemRed` by how likely the line is vulnerable (80% → 100%), at 45% opacity. */
export function riskBackground(probability: number): string {
  const t = Math.min(Math.max((probability - 0.8) / 0.2, 0), 1);
  const yellow = [255, 214, 10];
  const red = [255, 69, 58];
  const [r, g, b] = yellow.map((channel, index) => Math.round(channel + (red[index] - channel) * t));
  return `rgba(${r}, ${g}, ${b}, 0.45)`;
}

/** Opacity of the red marker bar the gutter draws beside a risky line. */
export function riskBarOpacity(probability: number): number {
  return 0.4 + 0.6 * Math.min(Math.max((probability - 0.8) / 0.2, 0), 1);
}

/** `SourceViewer.gutterWidth(for:)`: room for the digits, a marker dot and padding. */
export function gutterWidth(source: string): number {
  let lines = 1;
  for (let i = 0; i < source.length; i++) if (source.charCodeAt(i) === 10) lines++;
  return Math.max(1, String(lines).length) * 9 + 26;
}

/** Offset where each line starts (index N is line N + 1), splitting on "\n" only. */
export function lineStarts(source: string): number[] {
  const starts = [0];
  for (let i = 0; i < source.length; i++) if (source.charCodeAt(i) === 10) starts.push(i + 1);
  return starts;
}

/** `complementRanges(of:totalLength:)`: everything in [0, total) outside `range`. */
export function complementRanges(range: TextRange, total: number): TextRange[] {
  if (total <= 0) return [];
  const ranges: TextRange[] = [];
  if (range.location > 0) ranges.push({ location: 0, length: range.location });
  const end = range.location + range.length;
  if (end < total) ranges.push({ location: end, length: total - end });
  return ranges;
}

type Layer = "token" | "call" | "function" | "class" | "match" | "dim" | "risk";

interface Edge {
  pos: number;
  add: boolean;
  layer: Layer;
  value: string | number;
}

/**
 * Splits the text at every place a style starts or stops and gives each run its
 * combined styles. Foreground: a call site beats a function name beats a class
 * name beats the syntax colour (the order `clickableTarget` tests them in).
 * Background: a find match beats the focus dim beats the risk colour.
 */
export function buildSegments(input: HighlightInput): Segment[] {
  const total = input.source.length;
  const edges: Edge[] = [];
  const addRange = (layer: Layer, range: TextRange, value: string | number) => {
    const from = Math.max(0, range.location);
    const to = Math.min(total, range.location + range.length);
    if (to <= from) return;
    edges.push({ pos: from, add: true, layer, value }, { pos: to, add: false, layer, value });
  };

  for (const token of input.tokens) addRange("token", token, token.kind);
  for (const entry of input.callSites) addRange("call", entry, entry.name);
  for (const entry of input.functions) addRange("function", entry, entry.name);
  for (const entry of input.classes) addRange("class", entry, entry.name);
  for (const match of input.matches) addRange("match", match, 1);
  if (input.focus !== null && input.focus.length > 0) {
    for (const range of complementRanges(input.focus, total)) addRange("dim", range, 1);
  }
  const starts = lineStarts(input.source);
  for (const [lineText, probability] of Object.entries(input.riskLines)) {
    const line = Number(lineText);
    if (!Number.isInteger(line) || line < 1 || line > starts.length) continue;
    const start = starts[line - 1];
    const end = line < starts.length ? starts[line] - 1 : total;
    addRange("risk", { location: start, length: end - start }, probability);
  }
  edges.sort((a, b) => a.pos - b.pos);

  const active: Record<Layer, (string | number)[]> = {
    token: [],
    call: [],
    function: [],
    class: [],
    match: [],
    dim: [],
    risk: [],
  };
  const segments: Segment[] = [];
  let cursor = 0;
  for (const edge of edges) {
    if (edge.pos > cursor) {
      const segment = segmentFor(cursor, edge.pos, active);
      const previous = segments.at(-1);
      if (segment !== null) {
        const continues =
          previous !== undefined &&
          previous.to === segment.from &&
          previous.className === segment.className &&
          previous.style === segment.style &&
          previous.link?.kind === segment.link?.kind &&
          previous.link?.name === segment.link?.name;
        if (continues) previous.to = segment.to;
        else segments.push(segment);
      }
      cursor = edge.pos;
    }
    const stack = active[edge.layer];
    if (edge.add) stack.push(edge.value);
    else stack.splice(stack.lastIndexOf(edge.value), 1);
  }
  return segments;
}

function segmentFor(from: number, to: number, active: Record<Layer, (string | number)[]>): Segment | null {
  const classes: string[] = [];
  const token = active.token.at(-1);
  if (token !== undefined) classes.push(`tok-${token}`);

  let link: Segment["link"];
  const call = active.call.at(-1);
  const fn = active.function.at(-1);
  const cls = active.class.at(-1);
  if (call !== undefined) link = { kind: "call", name: String(call) };
  else if (fn !== undefined) link = { kind: "function", name: String(fn) };
  else if (cls !== undefined) link = { kind: "class", name: String(cls) };
  if (link) classes.push(`cm-link-${link.kind}`);

  let style = "";
  if (active.match.length > 0) style = SEARCH_BACKGROUND;
  else if (active.dim.length > 0) style = DIM_BACKGROUND;
  else {
    const risk = active.risk.at(-1);
    if (risk !== undefined) style = riskBackground(Number(risk));
  }

  if (classes.length === 0 && style === "") return null;
  return { from, to, className: classes.join(" "), style: style === "" ? "" : `background-color: ${style}`, link };
}
