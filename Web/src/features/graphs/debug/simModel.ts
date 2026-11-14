// The debugger simulation's data: the server's `SimStateDTO` and the rules the window
// applies to it (which source lines are in focus, what a stack row reads, when a
// play run goes on). Plain functions, so the rules can be tested.
import { lineStarts, type TextRange, type TokenRange } from "../../../lib/code/decorations";

/** The auto-step interval of the Play button (`Timer.scheduledTimer(withTimeInterval: 0.12)`). */
export const PLAY_INTERVAL_MS = 120;

export type SimStepMode = "over" | "into" | "back";

export interface SimParameter {
  index: number;
  name: string;
  typeHint: string;
  value: string;
  summary: string;
  isBuffer: boolean;
  capacity: number;
}

export interface SimWatchRow {
  name: string;
  value: string;
  changed: boolean;
  isParameter: boolean;
}

export interface SimFrame {
  index: number;
  functionName: string;
  fileName: string;
  path: string;
  line: number;
  isActive: boolean;
  isDone: boolean;
  isSelected: boolean;
}

export interface SimLineSpan {
  start: number;
  end: number;
}

/** `SimDebugService.SimStateDTO`: everything the debugger window shows. */
export interface SimState {
  loaded: boolean;
  title: string;
  functionName: string;
  badge: string;
  entryPath: string;
  displayedPath?: string | null;
  sourceText: string;
  currentLine: number;
  bodyLines?: SimLineSpan | null;
  statusText: string;
  finished: boolean;
  /** The index of the current step. It does not advance on every step; `stepCount` does. */
  stepNumber: number;
  /** The number of steps taken so far. */
  stepCount: number;
  parameters: SimParameter[];
  watchRows: SimWatchRow[];
  frames: SimFrame[];
  selectedFrameIndex: number;
  canStepOver: boolean;
  canStepInto: boolean;
  canPlay: boolean;
  canStepBack: boolean;
  canReset: boolean;
}

/** The text of the source pane: the displayed file with its syntax tokens. */
export interface SimSourceFile {
  path: string;
  text: string;
  tokens: TokenRange[];
}

/** The fields `focusRange` reads. */
export type SimScope = Pick<SimState, "bodyLines" | "displayedPath" | "entryPath">;

/** The range of 1-based `line`, without its line break. Nil when the line does not exist. */
export function lineRange(source: string, line: number): TextRange | null {
  const starts = lineStarts(source);
  if (line < 1 || line > starts.length) return null;
  const start = starts[line - 1];
  const end = line < starts.length ? starts[line] - 1 : source.length;
  return { location: start, length: end - start };
}

/**
 * The part of the source the simulation dims: everything outside the simulated function's
 * body. Only the entry file has a body, so the rule applies only while that file is shown.
 */
export function focusRange(state: SimScope, source: string): TextRange | null {
  if (!state.bodyLines || state.displayedPath !== state.entryPath) return null;
  const first = lineRange(source, state.bodyLines.start);
  const last = lineRange(source, state.bodyLines.end);
  if (!first || !last) return null;
  const end = last.location + last.length;
  return { location: first.location, length: end - first.location };
}

/** A stack row: "<function> — <file>:<line>". */
export function frameLabel(frame: SimFrame): string {
  return `${frame.functionName} — ${frame.fileName}:${frame.line}`;
}

/** The active frame reads blue, the others secondary. */
export function frameColor(frame: SimFrame): string {
  return frame.isActive ? "color: var(--system-blue)" : "color: var(--secondary-label)";
}

/** A variable that changed in the last step shows its name in orange. */
export function watchNameStyle(row: SimWatchRow): string | undefined {
  return row.changed ? "color: var(--system-orange)" : undefined;
}

export function playButtonTitle(playing: boolean): string {
  return playing ? "Pause" : "Play";
}

/**
 * Whether a step ran. A step over a finished simulation changes nothing, so a play run
 * stops on the first call that leaves the step count where it was.
 */
export function stepProduced(before: Pick<SimState, "stepCount">, after: Pick<SimState, "stepCount">): boolean {
  return after.stepCount > before.stepCount;
}
