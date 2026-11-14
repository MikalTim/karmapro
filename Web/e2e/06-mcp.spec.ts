import { expect, test } from "@playwright/test";
import { openFixture, pickMenuItem, windowTitled } from "./helpers";

test("the MCP service starts from Settings and answers initialize", async ({ page, request }) => {
  await openFixture(page);
  await pickMenuItem(page, "Karma Pro", "Settings…");
  const settings = windowTitled(page, "Settings");
  await expect(settings).toBeVisible();

  await settings.getByRole("button", { name: /Start/ }).click();
  await expect(settings.locator(".dot.running")).toBeVisible();
  const url = await settings.locator(".url").getAttribute("title");
  expect(url).toMatch(/^http:\/\/127\.0\.0\.1:87(6[5-9]|7[0-5])\/mcp\/[0-9a-f]+$/);

  const response = await request.post(url ?? "", {
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    data: {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "t", version: "1" } },
    },
  });
  expect(response.ok()).toBe(true);
  expect(await response.text()).toContain('"result"');
});
