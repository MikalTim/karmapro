import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ALL_LANGUAGES, reloadTree, setLanguage, treeState } from "./treeState.svelte";

function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

const fetchMock = vi.fn<typeof fetch>();

describe("tree state", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockReset();
    treeState.language = ALL_LANGUAGES;
    treeState.query = "";
    treeState.tree = null;
    treeState.error = null;
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("asks the server for the chosen language and the search text", async () => {
    fetchMock.mockResolvedValue(reply({ root: null, matches: null }));
    treeState.query = "main";

    setLanguage("C");
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledOnce());

    const [url] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/project/tree?language=C&query=main");
    expect(treeState.language).toBe("C");
  });

  it("keeps the newest reply when an older request answers last", async () => {
    const older = Promise.withResolvers<Response>();
    const newer = Promise.withResolvers<Response>();
    fetchMock.mockReturnValueOnce(older.promise).mockReturnValueOnce(newer.promise);

    treeState.query = "a";
    const first = reloadTree();
    treeState.query = "ab";
    const second = reloadTree();

    newer.resolve(reply({ root: null, matches: [{ name: "ab.c", path: "/p/ab.c", isDirectory: false }] }));
    await second;
    older.resolve(reply({ root: null, matches: [{ name: "a.c", path: "/p/a.c", isDirectory: false }] }));
    await first;

    expect(treeState.tree?.matches?.map((node) => node.name)).toEqual(["ab.c"]);
  });

  it("shows the server's message when the tree cannot be read", async () => {
    fetchMock.mockResolvedValue(reply({ error: 'Unknown language "Cobol".' }, 400));

    await reloadTree();

    expect(treeState.error).toBe('Unknown language "Cobol".');
    expect(treeState.tree).toBeNull();
  });
});
