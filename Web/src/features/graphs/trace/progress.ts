// The progress line of the windows that index the project first
// (`VariableFlowWindowController.updateProgress` and its Reachability twin).

/** "1s", "42s" or "3 min", as the windows write a time left. */
export function formatRemaining(seconds: number): string {
  if (seconds < 1) return "1s";
  if (seconds < 60) return `${Math.round(seconds)}s`;
  return `${Math.round(seconds / 60)} min`;
}

/**
 * The line under the bar. `elapsedSeconds` is the time since the search
 * started; the time left is extrapolated from the files done so far.
 */
export function indexedProgressText(done: number, total: number, elapsedSeconds: number): string {
  let eta: string;
  if (done <= 0) {
    eta = "estimating time…";
  } else if (done >= total) {
    eta = "finishing…";
  } else {
    const remaining = (elapsedSeconds * (total - done)) / done;
    eta = `about ${formatRemaining(remaining)} left`;
  }
  return `Indexed ${done} of ${total} source files — ${eta}`;
}

/** The bar's fill, 0...1, or undefined when the total is not known yet (the bar keeps its value). */
export function progressFraction(done: number, total: number): number | undefined {
  return total > 0 ? done / total : undefined;
}
