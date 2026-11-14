// The text and the bar of the index build window (`IndexBuildWindowController`).

/** Fraction of the bar filled, 0 until the total is known. */
export function indexFraction(done: number, total: number): number {
  return total > 0 ? done / total : 0;
}

/** `1s`, `42s` or `3 min`: the time left, written as the progress window writes it. */
export function formatRemaining(seconds: number): string {
  if (seconds < 1) return "1s";
  if (seconds < 60) return `${Math.round(seconds)}s`;
  return `${Math.round(seconds / 60)} min`;
}

/** The status line under the bar, estimated from how long the build has run so far. */
export function indexStatus(done: number, total: number, elapsedSeconds: number): string {
  let eta: string;
  if (done <= 0) eta = "estimating time…";
  else if (done >= total) eta = "finishing…";
  else eta = `about ${formatRemaining((elapsedSeconds * (total - done)) / done)} left`;
  return `Indexed ${done} of ${total} source files — ${eta}`;
}
