import { expect, test } from "@playwright/test";
import { openFixture, windowTitled } from "./helpers";

test("a saved open bug shows on the Bugs button and in the page title", async ({ page }) => {
  await openFixture(page);
  await page.getByRole("button", { name: "Bugs", exact: true }).click();
  const list = windowTitled(page, "Security bugs tracker");
  await expect(list).toBeVisible();
  await list.getByRole("button", { name: "New Bug" }).click();

  const editor = page.getByRole("dialog").filter({ has: page.getByPlaceholder("Short summary of the issue") });
  await editor.getByPlaceholder("Short summary of the issue").fill("T1");
  await editor.getByRole("button", { name: "Save" }).click();

  await expect(page.locator(".bugs .badge")).toHaveText("1");
  await expect(page).toHaveTitle(/^\(1\) /);
});
