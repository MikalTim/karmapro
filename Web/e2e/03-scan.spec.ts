import { expect, test, type Page } from "@playwright/test";
import { openFixture, windowTitled } from "./helpers";
import { readFile } from "node:fs/promises";

async function openScan(page: Page) {
  await page.getByRole("button", { name: "Security Scan", exact: true }).click();
  await page.getByRole("alertdialog").getByRole("button", { name: "Regular scan only" }).click();
  const scan = windowTitled(page, "Security Scan");
  await expect(scan).toBeVisible();
  return scan;
}

test("the scan lists the four findings, jumps to a line, hides an ignored finding for good and exports SARIF", async ({
  page,
}) => {
  await openFixture(page);
  const scan = await openScan(page);

  const rows = scan.locator(".tr");
  await expect(rows).toHaveCount(4, { timeout: 60_000 });
  const wanted: [string, string, string][] = [
    ["Buffer Overflow", "vuln.c", "6"],
    ["Command Injection", "vuln.c", "7"],
    ["Format String", "vuln.c", "8"],
    ["Command Injection", "app.py", "5"],
  ];
  for (const [category, file, line] of wanted) {
    const cell = (text: string) => page.getByRole("gridcell", { name: text, exact: true });
    await expect(rows.filter({ has: cell(category) }).filter({ has: cell(file) }).filter({ has: cell(line) })).toHaveCount(1);
  }

  const formatString = rows.filter({ hasText: "Format String" });
  await formatString.dblclick();
  await expect(page).toHaveTitle("project Project (vuln.c)");
  // The viewer selects the finding's line, so the selection box sits level with the gutter number 8.
  const selected = page.locator(".cm-selectionBackground").first();
  await expect(selected).toBeVisible();
  const selectionBox = await selected.boundingBox();
  const eighth = await page.locator(".karma-gutter .cm-gutterElement", { hasText: /^8$/ }).boundingBox();
  expect(Math.abs((selectionBox?.y ?? -100) - (eighth?.y ?? 100))).toBeLessThan(6);

  const exporting = page.waitForEvent("download");
  await scan.getByRole("button", { name: "Export Scan" }).click();
  const download = await exporting;
  expect(download.suggestedFilename()).toBe("KarmaPro-scan.sarif.json");
  const exported = await readFile(await download.path(), "utf8");
  expect(exported).toContain('"version" : "2.1.0"');

  await formatString.click();
  await scan.getByRole("button", { name: "Ignore issue" }).click();
  await expect(rows).toHaveCount(3);
  await expect(rows.filter({ hasText: "Format String" })).toHaveCount(0);

  await page.reload();
  await openFixture(page);
  const again = await openScan(page);
  await expect(again.locator(".tr")).toHaveCount(3, { timeout: 60_000 });
  await expect(again.locator(".tr").filter({ hasText: "Format String" })).toHaveCount(0);
});
