import { expect, test } from "@playwright/test";
import { openFixture, treeRow, windowTitled } from "./helpers";

test("a note saved from the gutter marks its line and is listed in the Notes window", async ({ page }) => {
  await openFixture(page);
  await treeRow(page, "vuln.c").click();
  await expect(page.locator(".karma-gutter .karma-line-number")).toHaveCount(11);

  await page.locator(".karma-gutter .cm-gutterElement", { hasText: /^6$/ }).click();
  const note = page.locator("textarea");
  await note.fill("check");
  await page.getByRole("button", { name: "Save" }).click();

  const sixth = page.locator(".karma-gutter .cm-gutterElement", { hasText: /^6$/ });
  await expect(sixth.locator(".karma-note-dot")).toBeVisible();

  await page.getByRole("button", { name: "Notes", exact: true }).click();
  const notes = windowTitled(page, "Notes");
  await expect(notes).toBeVisible();
  await expect(notes.getByText("check")).toBeVisible();
});
