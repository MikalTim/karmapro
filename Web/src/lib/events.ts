// One Server-Sent-Events connection to /api/events shared by the whole app.
//
// The server pushes live updates (job progress, bug count, AI stream, pull
// request changes, …). `on(type, handler)` subscribes to one event type and
// returns an unsubscribe function. The browser reconnects by itself when the
// connection drops.
import { tokenQuery } from "./api";

type Handler = (data: unknown) => void;

const handlers = new Map<string, Set<Handler>>();
const connectionListeners = new Set<(open: boolean) => void>();
let source: EventSource | null = null;

function attach(target: EventSource, type: string): void {
  target.addEventListener(type, (event) => {
    let data: unknown;
    try {
      data = JSON.parse((event as MessageEvent<string>).data);
    } catch {
      return;
    }
    handlers.get(type)?.forEach((handler) => handler(data));
  });
}

function connect(): EventSource {
  if (source) return source;
  const created = new EventSource("/api/events" + tokenQuery());
  created.onopen = () => connectionListeners.forEach((listener) => listener(true));
  created.onerror = () => connectionListeners.forEach((listener) => listener(created.readyState === EventSource.OPEN));
  for (const type of handlers.keys()) attach(created, type);
  source = created;
  return created;
}

/** Subscribes to an event type. Returns the unsubscribe function. */
export function on<T = unknown>(type: string, handler: (data: T) => void): () => void {
  let set = handlers.get(type);
  const first = !set;
  if (!set) {
    set = new Set();
    handlers.set(type, set);
  }
  const listeners = set;
  listeners.add(handler as Handler);
  // A new connection attaches every known type itself; an existing one only
  // needs the type that was just added.
  const connectionExisted = source !== null;
  const target = connect();
  if (first && connectionExisted) attach(target, type);
  return () => {
    listeners.delete(handler as Handler);
  };
}

/** Called with true when the stream opens and false when it drops. */
export function onConnection(listener: (open: boolean) => void): () => void {
  connectionListeners.add(listener);
  return () => connectionListeners.delete(listener);
}

/** Opens the stream now (it also opens on the first `on`). */
export function startEvents(): void {
  connect();
}

/** Test hook: forget the connection and every subscription. */
export function resetEventsForTests(): void {
  source?.close();
  source = null;
  handlers.clear();
  connectionListeners.clear();
}
