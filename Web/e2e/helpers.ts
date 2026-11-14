import { expect, type Locator, type Page } from "@playwright/test";
import { basename, dirname, resolve } from "node:path";
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
 * Loads the page, waits out the splash and opens a folder (the fixture by default) through the Open Folder panel,
 * the way a person starts the app. The project's name is the folder's name, which the window title shows.
 */
export async function openFixture(page: Page, folder: string = FIXTURE): Promise<void> {
  await page.goto("/");
  const picker = page.getByRole("dialog", { name: "Choose" });
  await expect(picker).toBeVisible({ timeout: 15_000 });
  const path = picker.getByLabel("Path");
  await path.fill(folder);
  const listed = page.waitForResponse((response) => response.url().includes("/api/fs/list") && response.ok());
  await path.press("Enter");
  await listed;
  await picker.getByRole("button", { name: "Browse" }).click();
  await expect(picker).toBeHidden();
  await expect(page).toHaveTitle(new RegExp(`${basename(folder)} Project`));
}

/** Opens a menu in the menu bar and picks an item. */
export async function pickMenuItem(page: Page, menu: string, item: string): Promise<void> {
  await page.getByRole("button", { name: menu, exact: true }).click();
  await page.getByText(item, { exact: true }).click();
}

/**
 * Records what a person would see go wrong while using the page: a console error, an uncaught exception,
 * or an API call that answered 4xx or 5xx. `problems()` returns the lines collected so far.
 */
export function watchProblems(page: Page): () => string[] {
  const found: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error") found.push(`console: ${message.text()}`);
  });
  page.on("pageerror", (error) => found.push(`exception: ${error.message}`));
  page.on("response", (response) => {
    if (response.url().includes("/api/") && response.status() >= 400) {
      found.push(`${response.status()} ${response.request().method()} ${new URL(response.url()).pathname}`);
    }
  });
  return () => found;
}

/** Saves a screenshot of the whole page for the side-by-side check against the AppKit window. */
export async function shoot(page: Page, name: string): Promise<void> {
  await page.screenshot({ path: `test-results/sweep/${name}.png` });
}

/**
 * Right-clicks the first occurrence of `word` in the source viewer and picks a context menu item. A word such as
 * `buf` is plain text inside a larger element, so its position is measured with a text range.
 */
export async function pickViewerMenuItem(page: Page, word: string, item: string | RegExp): Promise<void> {
  const point = await page.locator(".cm-content").evaluate((content, text) => {
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node !== null; node = walker.nextNode()) {
      const at = node.textContent?.indexOf(text) ?? -1;
      if (at < 0) continue;
      const range = document.createRange();
      range.setStart(node, at);
      range.setEnd(node, at + text.length);
      const box = range.getBoundingClientRect();
      return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
    }
    return null;
  }, word);
  expect(point, `"${word}" is shown in the source viewer`).not.toBeNull();
  await page.mouse.click(point?.x ?? 0, point?.y ?? 0, { button: "right" });
  await page.getByRole("menuitem", { name: item }).click();
}
