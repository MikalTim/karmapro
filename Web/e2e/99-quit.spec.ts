import { expect, test } from "@playwright/test";
import { openFixture, pickMenuItem } from "./helpers";

test("Quit asks for confirmation and then stops the server", async ({ page, request }) => {
  await openFixture(page);
  await pickMenuItem(page, "Karma Pro", "Quit Karma Pro");
  const alert = page.getByRole("alertdialog");
  await expect(alert).toBeVisible();

  await alert.getByRole("button", { name: "Cancel" }).click();
  await expect(alert).toBeHidden();
  expect((await request.get("/api/app/info", { headers: { "X-Karma-Client": "web" } })).ok()).toBe(true);

  await pickMenuItem(page, "Karma Pro", "Quit Karma Pro");
  await alert.getByRole("button", { name: "Quit" }).click();
  await expect
    .poll(async () => (await request.get("/api/app/info", { headers: { "X-Karma-Client": "web" } }).catch(() => null))?.ok() ?? false, {
      timeout: 15_000,
    })
    .toBe(false);
});
