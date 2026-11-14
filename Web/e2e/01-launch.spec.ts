import { expect, test } from "@playwright/test";
import { openFixture, treeRow } from "./helpers";

test("the splash goes away after about 3 seconds, the folder panel opens and the fixture's files are listed", async ({
  page,
}) => {
  await page.goto("/");
  const splash = page.locator(".splash-layer");
  await expect(splash).toBeVisible();
  await expect(splash.locator("img")).toHaveJSProperty("complete", true);
  await expect(splash).toBeHidden({ timeout: 6_000 });
  await expect(page.getByRole("dialog", { name: "Choose" })).toBeVisible();

  await openFixture(page);
  await expect(treeRow(page, "app.py")).toBeVisible();
  await expect(treeRow(page, "vuln.c")).toBeVisible();
  await expect(page).toHaveTitle("project Project");
});
