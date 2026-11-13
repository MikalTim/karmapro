import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ApiError, api, dispositionFileName, upload, withQuery } from "./api";

function reply(body: unknown, init: ResponseInit = { status: 200 }): Response {
  return new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json" }, ...init });
}

describe("withQuery", () => {
  it("skips undefined and null values and encodes the rest", () => {
    expect(withQuery("/api/x", { a: 1, b: undefined, c: null, d: "x y", e: false })).toBe("/api/x?a=1&d=x+y&e=false");
  });

  it("appends to an existing query string", () => {
    expect(withQuery("/api/x?a=1", { b: 2 })).toBe("/api/x?a=1&b=2");
  });

  it("returns the path unchanged without parameters", () => {
    expect(withQuery("/api/x")).toBe("/api/x");
    expect(withQuery("/api/x", {})).toBe("/api/x");
  });
});

describe("dispositionFileName", () => {
  it("reads quoted, unquoted and RFC 5987 names", () => {
    expect(dispositionFileName('attachment; filename="KarmaPro-scan.sarif.json"')).toBe("KarmaPro-scan.sarif.json");
    expect(dispositionFileName("attachment; filename=report.txt")).toBe("report.txt");
    expect(dispositionFileName("attachment; filename*=UTF-8''na%C3%AFve.txt")).toBe("naïve.txt");
    expect(dispositionFileName(null)).toBeNull();
    expect(dispositionFileName("inline")).toBeNull();
  });
});

describe("api", () => {
  const fetchMock = vi.fn<typeof fetch>();

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockReset();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("sends the client header and a JSON body, and decodes the reply", async () => {
    fetchMock.mockResolvedValue(reply({ ok: true }));

    const result = await api<{ ok: boolean }>("POST", "/api/project/open", { path: "/tmp/p" });

    expect(result).toEqual({ ok: true });
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/project/open");
    expect(init?.method).toBe("POST");
    expect(init?.body).toBe('{"path":"/tmp/p"}');
    const headers = init?.headers as Record<string, string>;
    expect(headers["X-Karma-Client"]).toBe("web");
    expect(headers["Content-Type"]).toBe("application/json");
  });

  it("turns the server's error field into the ApiError message", async () => {
    fetchMock.mockResolvedValue(reply({ error: "No Folder Open" }, { status: 400, statusText: "Bad Request" }));

    const error = await api("GET", "/api/scan").catch((e: unknown) => e);

    expect(error).toBeInstanceOf(ApiError);
    expect((error as ApiError).status).toBe(400);
    expect((error as ApiError).message).toBe("No Folder Open");
  });

  it("falls back to the status line when the reply is not JSON", async () => {
    fetchMock.mockResolvedValue(new Response("boom", { status: 502, statusText: "Bad Gateway" }));

    const error = await api("GET", "/api/x").catch((e: unknown) => e);

    expect((error as ApiError).message).toBe("502 Bad Gateway");
  });

  it("uploads raw bytes with the file name in the query", async () => {
    fetchMock.mockResolvedValue(reply({ imported: 1 }));

    const file = new File(["{}"], "notes.json");
    await upload("/api/notes/import", file, { password: "pw" });

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/notes/import?filename=notes.json&password=pw");
    expect((init?.headers as Record<string, string>)["Content-Type"]).toBe("application/octet-stream");
    expect(init?.body).toBe(file);
  });
});
