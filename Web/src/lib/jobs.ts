// Long-running work on the server (index builds, scans, flows, training, …)
// runs as a job. The endpoint that starts it answers `{ jobId }`; progress and
// completion arrive as events, and the result is fetched from /api/jobs/:id.
import { api } from "./api";
import { on } from "./events";

export type JobStatus = "queued" | "running" | "completed" | "failed" | "cancelled";

export interface Job<T = unknown> {
  id: string;
  kind: string;
  status: JobStatus;
  done: number;
  total: number;
  stage: string;
  error?: string;
  result?: T;
}

export interface JobProgress {
  id: string;
  kind: string;
  done: number;
  total: number;
  stage: string;
}

export interface JobOutcome<T> {
  status: "completed" | "cancelled";
  result: T | undefined;
}

export interface JobHandle<T> {
  /** Resolves when the job completes or is cancelled; rejects when it fails. */
  promise: Promise<JobOutcome<T>>;
  id: string;
  cancel(): Promise<void>;
}

export interface RunningJob<T> {
  promise: Promise<JobOutcome<T>>;
  cancel(): Promise<void>;
}

/** How often a job is polled in case an event was missed. */
const POLL_MS = 2000;

/** Follows an already-started job. */
export function trackJob<T = unknown>(id: string, onProgress?: (progress: JobProgress) => void): JobHandle<T> {
  const { promise, resolve, reject } = Promise.withResolvers<JobOutcome<T>>();
  const unsubscribers: Array<() => void> = [];
  let timer: number | undefined;
  let finished = false;

  const finish = () => {
    finished = true;
    unsubscribers.splice(0).forEach((unsubscribe) => unsubscribe());
    clearInterval(timer);
  };

  const check = async () => {
    if (finished) return;
    let job: Job<T>;
    try {
      job = await api<Job<T>>("GET", `/api/jobs/${id}`);
    } catch (error) {
      if (finished) return;
      finish();
      reject(error);
      return;
    }
    if (finished) return;
    if (job.status === "queued" || job.status === "running") {
      onProgress?.({ id, kind: job.kind, done: job.done, total: job.total, stage: job.stage });
      return;
    }
    finish();
    if (job.status === "failed") reject(new Error(job.error || "The job failed."));
    else resolve({ status: job.status, result: job.result });
  };

  unsubscribers.push(
    on<JobProgress>("job.progress", (progress) => {
      if (progress.id === id) onProgress?.(progress);
    }),
    on<{ id: string }>("job.finished", (event) => {
      if (event.id === id) void check();
    }),
  );
  timer = setInterval(() => void check(), POLL_MS);
  // The job may have finished before the subscription existed.
  void check();

  return {
    promise,
    id,
    async cancel() {
      await api("DELETE", `/api/jobs/${id}`);
      await check();
    },
  };
}

/**
 * Starts a job (the promise is the call to the starting endpoint) and follows it.
 * `cancel` waits for the start call to answer, since the job id comes from it.
 */
export function runJob<T = unknown>(
  start: Promise<{ jobId: string }>,
  onProgress?: (progress: JobProgress) => void,
): RunningJob<T> {
  let handle: JobHandle<T> | undefined;
  const promise = start.then((started) => {
    handle = trackJob<T>(started.jobId, onProgress);
    return handle.promise;
  });
  return {
    promise,
    async cancel() {
      await start;
      await handle?.cancel();
    },
  };
}
