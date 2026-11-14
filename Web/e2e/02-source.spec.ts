import { expect, test } from "@playwright/test";
import { openFixture, treeRow } from "./helpers";

test("opening vuln.c colours keywords and numbers the lines 1 to 10", async ({ page }) => {
  await openFixture(page);
  await treeRow(page, "vuln.c").click();
  await expect(page).toHaveTitle("project Project (vuln.c)");

  await expect(page.locator(".tok-keyword", { hasText: /^char$/ }).first()).toBeVisible();
  // The file ends with a newline, so the gutter also numbers the empty last line (11), as the AppKit ruler does.
  const numbers = page.locator(".karma-gutter .karma-line-number");
  await expect(numbers).toHaveText(["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"]);
});
