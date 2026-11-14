import { expect, test } from "@playwright/test";
import { spawn } from "node:child_process";
import { join } from "node:path";
import { openFixture, windowTitled } from "./helpers";

test("a wiki page keeps its bold text and its link, and the link opens the page it names", async ({ page }) => {
  await openFixture(page);
  await page.getByRole("button", { name: "Wiki", exact: true }).click();
  const list = windowTitled(page, "Wiki");
  await expect(list).toBeVisible();

  await list.getByRole("button", { name: "New Page" }).click();
  const prompt = page.getByRole("alertdialog");
  await prompt.getByRole("textbox").fill("Alpha");
  await prompt.getByRole("button", { name: "OK" }).click();

  // The editor window carries the page's title once the page is loaded.
  const editorWindow = windowTitled(page, "Alpha");
  await expect(editorWindow).toBeVisible();
  const body = editorWindow.locator(".wiki-editor");
  await body.click();
  await page.keyboard.type("hello");
  await page.keyboard.press("Control+a");
  await editorWindow.getByRole("button", { name: "B", exact: true }).click();
  await page.keyboard.press("End");
  await page.keyboard.type(" [[Beta]]");
  await editorWindow.getByRole("button", { name: "Save" }).click();

  await editorWindow.getByRole("button", { name: "Close" }).click();
  await expect(editorWindow).toBeHidden();
  await list.getByRole("row", { name: /Alpha/ }).dblclick();

  const reopened = windowTitled(page, "Alpha");
  // Bold text is a span with the wiki-bold class; a link is an anchor that carries its target.
  await expect(reopened.locator(".wiki-editor .wiki-bold").filter({ hasText: "hello" })).toBeVisible();
  await reopened.locator(".wiki-editor a[data-link]").click();

  // The link closes this editor and opens the page it names, whose window carries that page's title.
  await expect(windowTitled(page, "Beta").locator("input.title")).toHaveValue("Beta");
});

interface WikiRunDTO {
  text: string;
  bold: boolean;
  link?: string | null;
}

interface WikiPageDTO {
  info: { slug: string; title: string };
  document: { paragraphs: { runs: WikiRunDTO[] }[] };
}

test("a second server on the same home still reads Alpha with bold text and the link, and the MCP token that was rotated", async ({
  request,
}) => {
  // A setting written on the first server (the MCP access token lives in UserDefaults, which Linux writes only when
  // told to) must be on disk for the second one.
  const rotated = await request.post("/api/mcp/rotate-token", { headers: { "X-Karma-Client": "web" } });
  expect(rotated.ok()).toBe(true);
  const rotatedUrl: { url: string } = await rotated.json();
  const port = 8793;
  const home = process.env.KARMA_E2E_HOME ?? "";
  const headers = { "X-Karma-Client": "web" };
  const second = spawn(process.env.KARMA_BIN ?? "../.build/release/karma", ["--serve", "--port", String(port)], {
    env: { ...process.env, HOME: home, XDG_DATA_HOME: join(home, ".local/share"), XDG_CONFIG_HOME: join(home, ".config") },
    stdio: "ignore",
  });
  try {
    const base = `http://127.0.0.1:${port}`;
    await expect
      .poll(async () => (await request.get(`${base}/api/app/info`, { headers }).catch(() => null))?.ok() ?? false, {
        timeout: 20_000,
      })
      .toBe(true);

    const reread = await request.get(`${base}/api/wiki/alpha`, { headers });
    expect(reread.ok()).toBe(true);
    const page: WikiPageDTO = await reread.json();
    const runs = page.document.paragraphs.flatMap((paragraph) => paragraph.runs);
    expect(runs.find((run) => run.text.includes("hello"))?.bold).toBe(true);
    expect(runs.some((run) => run.link === "wiki://page/Beta")).toBe(true);

    const mcp = await request.get(`${base}/api/mcp`, { headers });
    const state: { url: string } = await mcp.json();
    expect(state.url.split("/").pop()).toBe(rotatedUrl.url.split("/").pop());
  } finally {
    second.kill();
  }
});
