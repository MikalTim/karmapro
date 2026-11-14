import { expect, test } from "@playwright/test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { openFixture, treeRow, windowTitled } from "./helpers";

// Windows built with `EscClosableWindow` in AppKit close on Escape; the key goes to the window that is key, which in
// the page is the newest one unless the key was typed in the main window's own panes.

test("Escape closes a window opened from the toolbar, whose button still has the focus", async ({ page }) => {
  await openFixture(page);
  await page.getByRole("button", { name: "Notes", exact: true }).click();
  const notes = windowTitled(page, "Notes — project");
  await expect(notes).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(notes).toBeHidden();
});

test("Escape closes the definition window at once, and also from inside it, but not when typed in the main viewer", async ({
  page,
}) => {
  const folder = mkdtempSync(join(tmpdir(), "karma-e2e-escape-"));
  writeFileSync(join(folder, "a.c"), "int helper(int x) {\n    return x + 1;\n}\nint main(void) {\n    return helper(2);\n}\n");
  await openFixture(page, folder);
  await treeRow(page, "a.c").click();
  const callSite = page.locator("[data-link-kind]", { hasText: "helper" }).last();
  const definition = windowTitled(page, "Definition — a.c");

  // The click that opened the window left the focus in the viewer; the new window is the key window, so Escape
  // goes straight to it.
  await callSite.click();
  await expect(definition).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(definition).toBeHidden();

  // A key typed in the main viewer is for the main window: the definition window stays.
  await callSite.click();
  await expect(definition).toBeVisible();
  await page.locator(".cm-content").first().click({ position: { x: 5, y: 5 } });
  await page.keyboard.press("Escape");
  await expect(definition).toBeVisible();

  await definition.locator(".cm-content").click();
  await page.keyboard.press("Escape");
  await expect(definition).toBeHidden();
});
