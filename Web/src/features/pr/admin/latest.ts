// Tracks overlapping requests so that only the newest one's answer is applied. The user can type faster
// than the server answers, and an older answer must not overwrite the result of what is on screen now.

export interface Latest {
  /** Starts a request and returns its ticket. */
  next(): number;
  /** True while no newer request has started since `ticket`. */
  isLatest(ticket: number): boolean;
}

export function createLatest(): Latest {
  let current = 0;
  return {
    next: () => ++current,
    isLatest: (ticket) => ticket === current,
  };
}
