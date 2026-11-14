import { expect, type Locator, type Page } from "@playwright/test";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

/** The folder the specs open: `vuln.c` and `app.py`, whose findings the scan spec expects. */
export const FIXTURE = resolve(dirname(fileURLToPath(import.meta.url)), "../tests/fixtures/project");

/** The window the page shows for a title (`role="dialog"`, labelled by the title bar). */
export function windowTitled(page: Page, title: string): Locator {
  return page.getByRole("dialog", { name: title, exact: true });
}

/** A file row in the tree. */
export function treeRow(page: Page, name: string): Locator {
  return page.getByRole("treeitem", { name }).first();
}

/**
 * Loads the page, waits out the splash and opens the fixture folder through the Open Folder panel,
 * the way a person starts the app.
 */
export async function openFixture(page: Page): Promise<void> {
  await page.goto("/");
  const picker = page.getByRole("dialog", { name: "Choose" });
  await expect(picker).toBeVisible({ timeout: 15_000 });
  const path = picker.getByLabel("Path");
  await path.fill(FIXTURE);
  const listed = page.waitForResponse((response) => response.url().includes("/api/fs/list") && response.ok());
  await path.press("Enter");
  await listed;
  await picker.getByRole("button", { name: "Browse" }).click();
  await expect(picker).toBeHidden();
  await expect(page).toHaveTitle(/project Project/);
}

/** Opens a menu in the menu bar and picks an item. */
export async function pickMenuItem(page: Page, menu: string, item: string): Promise<void> {
  await page.getByRole("button", { name: menu, exact: true }).click();
  await page.getByText(item, { exact: true }).click();
}
