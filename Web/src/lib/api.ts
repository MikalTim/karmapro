// Client for the Karma Pro server's JSON API.
//
// Every request carries `X-Karma-Client: web` (the server refuses requests
// without it, which blocks cross-site form posts). When the server was started
// with a non-loopback host it prints a URL ending in `?token=…`; the token is
// moved into sessionStorage once, removed from the address bar, and sent as a
// bearer token from then on.

const TOKEN_KEY = "karma.token";

export class ApiError extends Error {
  readonly status: number;
  readonly body: unknown;

  constructor(status: number, message: string, body?: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.body = body;
  }
}

/** Moves `?token=` from the address bar into sessionStorage. Safe to call twice. */
export function captureToken(): void {
  if (typeof location === "undefined" || typeof sessionStorage === "undefined") return;
  const url = new URL(location.href);
  const token = url.searchParams.get("token");
  if (!token) return;
  sessionStorage.setItem(TOKEN_KEY, token);
  url.searchParams.delete("token");
  const query = url.searchParams.toString();
  history.replaceState(null, "", url.pathname + (query ? `?${query}` : "") + url.hash);
}

captureToken();

export function storedToken(): string | null {
  if (typeof sessionStorage === "undefined") return null;
  return sessionStorage.getItem(TOKEN_KEY);
}

/** `?token=…` for the event stream (EventSource cannot set headers), or "". */
export function tokenQuery(): string {
  const token = storedToken();
  return token ? `?token=${encodeURIComponent(token)}` : "";
}

function headers(extra?: Record<string, string>): Record<string, string> {
  const h: Record<string, string> = { "X-Karma-Client": "web", ...extra };
  const token = storedToken();
  if (token) h["Authorization"] = `Bearer ${token}`;
  return h;
}

async function fail(response: Response): Promise<never> {
  let message = `${response.status} ${response.statusText}`.trim();
  let body: unknown;
  try {
    body = await response.json();
    const error = (body as { error?: unknown } | null)?.error;
    if (typeof error === "string" && error) message = error;
  } catch {
    // Not JSON: keep the status line.
  }
  throw new ApiError(response.status, message, body);
}

/** Builds `path?a=1&b=2`, skipping undefined values. */
export function withQuery(path: string, params?: Record<string, string | number | boolean | undefined | null>): string {
  if (!params) return path;
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null) continue;
    search.set(key, String(value));
  }
  const query = search.toString();
  return query ? `${path}${path.includes("?") ? "&" : "?"}${query}` : path;
}

/** Sends a JSON request and returns the decoded JSON reply. */
export async function api<T = unknown>(method: string, path: string, body?: unknown): Promise<T> {
  const init: RequestInit = { method, headers: headers(body === undefined ? undefined : { "Content-Type": "application/json" }) };
  if (body !== undefined) init.body = JSON.stringify(body);
  const response = await fetch(path, init);
  if (!response.ok) return fail(response);
  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

/** Like `api` for replies that are plain text or HTML. */
export async function apiText(method: string, path: string): Promise<string> {
  const response = await fetch(path, { method, headers: headers() });
  if (!response.ok) return fail(response);
  return response.text();
}

/** Fetches a binary reply (an image) with the API headers, which an `<img src>` cannot send. */
export async function apiBlob(path: string): Promise<Blob> {
  const response = await fetch(path, { headers: headers() });
  if (!response.ok) return fail(response);
  return response.blob();
}

/** The file name in a `Content-Disposition: attachment; filename="…"` header. */
export function dispositionFileName(header: string | null): string | null {
  if (!header) return null;
  const star = /filename\*=UTF-8''([^;]+)/i.exec(header);
  if (star) {
    try {
      return decodeURIComponent(star[1].trim());
    } catch {
      // fall through to the plain form
    }
  }
  const plain = /filename="?([^";]+)"?/i.exec(header);
  return plain ? plain[1].trim() : null;
}

/** Fetches `path` and saves the reply through the browser's download mechanism. */
export async function download(
  path: string,
  init?: { method?: string; body?: unknown; fallbackName?: string },
): Promise<string> {
  const method = init?.method ?? "GET";
  const request: RequestInit = {
    method,
    headers: headers(init?.body === undefined ? undefined : { "Content-Type": "application/json" }),
  };
  if (init?.body !== undefined) request.body = JSON.stringify(init.body);
  const response = await fetch(path, request);
  if (!response.ok) return fail(response);
  const name = dispositionFileName(response.headers.get("Content-Disposition")) ?? init?.fallbackName ?? "download";
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
  return name;
}

/** Posts a file's raw bytes (`application/octet-stream`) with its name as `?filename=`. */
export async function upload<T = unknown>(
  path: string,
  file: File | Blob,
  params?: Record<string, string | number | boolean | undefined | null>,
): Promise<T> {
  const name = file instanceof File ? file.name : "upload";
  const url = withQuery(path, { filename: name, ...params });
  const response = await fetch(url, {
    method: "POST",
    headers: headers({ "Content-Type": "application/octet-stream" }),
    body: file,
  });
  if (!response.ok) return fail(response);
  return (await response.json()) as T;
}
