import { expect, test, type Page } from "@playwright/test";
import { openFixture, pickMenuItem, pickViewerMenuItem, shoot, treeRow, watchProblems, windowTitled } from "./helpers";

// Opens every window of the feature parity map on the fixture folder and fails on anything a person would see go
// wrong: a console error, an uncaught exception or an API call answering 4xx or 5xx. Each window is also saved as
// test-results/sweep/<name>.png for the side-by-side check against its AppKit counterpart.

/** A window a feature opened: the newest dialog that is not the folder picker. */
function openWindows(page: Page) {
  return page.getByRole("dialog").filter({ hasNot: page.getByLabel("Path") });
}

async function openSource(page: Page): Promise<() => string[]> {
  const problems = watchProblems(page);
  await openFixture(page);
  await treeRow(page, "vuln.c").click();
  await expect(page.locator(".cm-content").getByText("main", { exact: true }).first()).toBeVisible();
  return problems;
}

async function settle(page: Page, name: string, problems: () => string[]): Promise<void> {
  await page.waitForTimeout(1500);
  await shoot(page, name);
  expect(problems()).toEqual([]);
}

test.describe("graph windows from the source viewer's context menu", () => {
  const items: [string, string, RegExp][] = [
    ["data-flow", "main", /Show Flow Diagram for main/],
    ["simulate", "main", /Simulate 'main' in the Debugger/],
    ["reachability", "main", /Show reachability of 'main'/],
    ["complexity", "main", /Complexity distribution/],
    ["follow-variable", "buf", /Follow the variable 'buf'/],
    ["backtrace", "main", /Backtrace Analyser/],
    ["entries", "main", /Find external entries/],
  ];
  for (const [name, word, item] of items) {
    test(name, async ({ page }) => {
      const problems = await openSource(page);
      await pickViewerMenuItem(page, word, item);
      await expect(openWindows(page).first()).toBeVisible();
      await settle(page, name, problems);
    });
  }

  test("how to fix it opens the AI assistant with the question", async ({ page }) => {
    const problems = await openSource(page);
    await pickViewerMenuItem(page, "strcpy", /How to fix it/);
    await expect(openWindows(page).first()).toBeVisible();
    await settle(page, "how-to-fix", problems);
  });

  test("clicking a function shows its flow chart in the flow panel", async ({ page }) => {
    const problems = await openSource(page);
    await page.locator(".cm-content").getByText("main", { exact: true }).first().click();
    await expect(page.getByText(/Cyclomatic complexity/)).toBeVisible();
    await settle(page, "flow-panel", problems);
  });
});

test.describe("toolbar and menu windows", () => {
  test("search in files", async ({ page }) => {
    const problems = watchProblems(page);
    await openFixture(page);
    await page.getByRole("button", { name: "Search in Files", exact: true }).click();
    await expect(openWindows(page).first()).toBeVisible();
    await settle(page, "search-files", problems);
  });

  test("train ML", async ({ page }) => {
    const problems = watchProblems(page);
    await openFixture(page);
    await page.getByRole("button", { name: "Train ML", exact: true }).click();
    await expect(windowTitled(page, "Train Bayesian Classifier")).toBeVisible();
    await settle(page, "ml-train", problems);
  });

  test("ML scan", async ({ page }) => {
    const problems = watchProblems(page);
    await openFixture(page);
    await page.getByRole("button", { name: "ML Scan", exact: true }).click();
    await settle(page, "ml-scan", problems);
  });

  test("AI assistant and providers", async ({ page }) => {
    const problems = watchProblems(page);
    await openFixture(page);
    await page.getByRole("button", { name: "AI", exact: true }).click();
    await expect(openWindows(page).first()).toBeVisible();
    await shoot(page, "ai");
    await settle(page, "ai-after", problems);
  });

  test("licensing", async ({ page }) => {
    const problems = watchProblems(page);
    await openFixture(page);
    await pickMenuItem(page, "Licensing", "Scan Licenses");
    await expect(openWindows(page).first()).toBeVisible();
    await settle(page, "licensing", problems);
  });

  test("packages", async ({ page }) => {
    const problems = watchProblems(page);
    await openFixture(page);
    await pickMenuItem(page, "Packages", "Scan project's packages");
    await settle(page, "packages", problems);
  });

  test("help", async ({ page }) => {
    const problems = watchProblems(page);
    await openFixture(page);
    await pickMenuItem(page, "Help", "Karma Pro Help");
    await expect(openWindows(page).first()).toBeVisible();
    await settle(page, "help", problems);
  });

  test("about and update checks", async ({ page }) => {
    const problems = watchProblems(page);
    await openFixture(page);
    await pickMenuItem(page, "Karma Pro", "About Karma Pro");
    await settle(page, "about", problems);
    await page.getByRole("button", { name: "Karma Pro", exact: true }).click();
    await shoot(page, "karma-menu");
    expect(problems()).toEqual([]);
  });
});

test.describe("pull request windows", () => {
  test("the PR menu, accounts and watched repositories", async ({ page }) => {
    const problems = watchProblems(page);
    await openFixture(page);
    await page.getByRole("button", { name: /Pull request monitoring/ }).click();
    await shoot(page, "pr-menu");
    await page.getByRole("menuitem", { name: /Accounts/ }).click();
    await expect(openWindows(page).first()).toBeVisible();
    await shoot(page, "pr-accounts");
    await page.getByRole("button", { name: /Pull request monitoring/ }).click();
    await page.getByRole("menuitem", { name: /Repositor/ }).click();
    await settle(page, "pr-repos", problems);
  });
});
