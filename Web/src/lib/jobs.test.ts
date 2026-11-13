import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { runJob, trackJob } from "./jobs";

type Listener = (data: unknown) => void;
const listeners = vi.hoisted(() => new Map<string, Set<(data: unknown) => void>>());

vi.mock("./events", () => ({
  on: (type: string, handler: Listener) => {
    const set = listeners.get(type) ?? new Set<Listener>();
    set.add(handler);
    listeners.set(type, set);
    return () => set.delete(handler);
  },
}));

function emit(type: string, data: unknown) {
  listeners.get(type)?.forEach((listener) => listener(data));
}

function job(status: string, extra: Record<string, unknown> = {}) {
  return { id: "j1", kind: "scan", status, done: 1, total: 4, stage: "parsing", ...extra };
}

describe("trackJob", () => {
  const fetchMock = vi.fn<typeof fetch>();

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockReset();
    listeners.clear();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  const respondWith = (...jobs: unknown[]) => {
    for (const next of jobs) {
      fetchMock.mockResolvedValueOnce(new Response(JSON.stringify(next), { headers: { "Content-Type": "application/json" } }));
    }
  };

  it("resolves with the result when the job had already finished", async () => {
    respondWith(job("completed", { result: { rows: 3 } }));

    const handle = trackJob<{ rows: number }>("j1");

    await expect(handle.promise).resolves.toEqual({ status: "completed", result: { rows: 3 } });
    // Finished: the progress and finish subscriptions are gone.
    expect([...listeners.values()].every((set) => set.size === 0)).toBe(true);
  });

  it("reports progress events for its own job only and finishes on job.finished", async () => {
    respondWith(job("running"));
    const progress: number[] = [];
    const handle = trackJob("j1", (p) => progress.push(p.done));
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));

    emit("job.progress", { id: "other", kind: "scan", done: 9, total: 9, stage: "x" });
    emit("job.progress", { id: "j1", kind: "scan", done: 2, total: 4, stage: "y" });
    respondWith(job("completed", { result: "done" }));
    emit("job.finished", { id: "j1", kind: "scan", status: "completed" });

    await expect(handle.promise).resolves.toEqual({ status: "completed", result: "done" });
    expect(progress).toContain(2);
    expect(progress).not.toContain(9);
  });

  it("rejects with the job's error when it fails", async () => {
    respondWith(job("failed", { error: "Out of memory" }));

    await expect(trackJob("j1").promise).rejects.toThrow("Out of memory");
  });

  it("resolves cancelled jobs with their partial result", async () => {
    respondWith(job("cancelled", { result: [1] }));

    await expect(trackJob("j1").promise).resolves.toEqual({ status: "cancelled", result: [1] });
  });
});

describe("runJob", () => {
  const fetchMock = vi.fn<typeof fetch>();

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockReset();
    listeners.clear();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("follows the job the start call returns", async () => {
    fetchMock.mockResolvedValueOnce(new Response(JSON.stringify(job("completed", { result: 7 }))));

    const running = runJob<number>(Promise.resolve({ jobId: "j1" }));

    await expect(running.promise).resolves.toEqual({ status: "completed", result: 7 });
    expect(fetchMock.mock.calls[0][0]).toBe("/api/jobs/j1");
  });

  it("cancels through DELETE once the job id is known", async () => {
    fetchMock.mockResolvedValueOnce(new Response(JSON.stringify(job("running"))));
    const running = runJob<number>(Promise.resolve({ jobId: "j1" }));
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));

    fetchMock.mockResolvedValueOnce(new Response(JSON.stringify(job("cancelled"))));
    fetchMock.mockResolvedValueOnce(new Response(JSON.stringify(job("cancelled", { result: 1 }))));
    await running.cancel();

    expect(fetchMock.mock.calls[1][1]?.method).toBe("DELETE");
    await expect(running.promise).resolves.toEqual({ status: "cancelled", result: 1 });
  });
});
