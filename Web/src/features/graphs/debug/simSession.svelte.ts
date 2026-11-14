// The debugger simulation's session. The server keeps one session for every browser
// tab, as the AppKit app keeps one debugger window. This store sends each action to
// the server, keeps the state it returns, and runs the Play button's timer.
import { api, withQuery } from "../../../lib/api";
import { showAlert } from "../../../lib/ui/alert.svelte";
import {
  PLAY_INTERVAL_MS,
  stepProduced,
  type SimSourceFile,
  type SimState,
  type SimStepMode,
} from "./simModel";

export const sim = $state<{
  state: SimState | null;
  /** The shown file with its tokens. Nil until it loads; the state's own text is shown meanwhile. */
  source: SimSourceFile | null;
  playing: boolean;
}>({ state: null, source: null, playing: false });

let playTimer: number | undefined;
/** Actions sent and not yet answered. A play tick waits for them, so steps never overlap. */
let pending = 0;
let sourceRun = 0;

/** Loads `functionName` from `path` (`SimDebugWindowController.reload`). Nil when the load failed. */
export async function loadSimulation(path: string, functionName: string): Promise<SimState | null> {
  stopPlaying();
  return send(api<SimState>("POST", "/api/sim/load", { path, function: functionName }));
}

/** One step, as the Step Over, Step Into and Step Back buttons do. Each one stops a running Play. */
export async function stepSimulation(mode: SimStepMode): Promise<void> {
  stopPlaying();
  await send(api<SimState>("POST", "/api/sim/step", { mode }));
}

export async function resetSimulation(): Promise<void> {
  stopPlaying();
  await send(api<SimState>("POST", "/api/sim/reset"));
}

/** Play runs the step-over loop on a timer; a second press pauses it. */
export function togglePlaying(): void {
  if (sim.playing) {
    stopPlaying();
    return;
  }
  sim.playing = true;
  playTimer = window.setInterval(() => void playTick(), PLAY_INTERVAL_MS);
}

export function stopPlaying(): void {
  if (playTimer !== undefined) window.clearInterval(playTimer);
  playTimer = undefined;
  sim.playing = false;
}

/** Sets parameter `index` from its text. It takes effect at the next reset. */
export async function setSimParameter(index: number, text: string): Promise<void> {
  await send(api<SimState>("PUT", "/api/sim/param", { index, text }));
}

/** Chooses the frame whose variables the watch table shows. */
export async function selectSimFrame(index: number): Promise<void> {
  await send(api<SimState>("POST", "/api/sim/frame", { index }));
}

/** Reads the displayed file's text and tokens. A failed read leaves the state's text shown without colours. */
export async function loadSimSource(path: string): Promise<void> {
  const run = ++sourceRun;
  try {
    const file = await api<SimSourceFile>("GET", withQuery("/api/file", { path }));
    if (run === sourceRun) sim.source = file;
  } catch {
    if (run === sourceRun) sim.source = null;
  }
}

async function playTick(): Promise<void> {
  const before = sim.state;
  if (!before || pending > 0) return;
  const after = await send(api<SimState>("POST", "/api/sim/step", { mode: "over" }));
  if (!after || !stepProduced(before, after)) stopPlaying();
}

/** Sends one action, publishes the state it returns and reports a failure. */
async function send(request: Promise<SimState>): Promise<SimState | null> {
  pending++;
  try {
    const dto = await request;
    sim.state = dto;
    return dto;
  } catch (error) {
    await showAlert({ message: error instanceof Error ? error.message : String(error), style: "warning" });
    return null;
  } finally {
    pending--;
  }
}
