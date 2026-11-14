import { expect, test } from "@playwright/test";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { openFixture, pickMenuItem } from "./helpers";

// Quit runs against its own server with its own home, so the process's exit status can be read: a crash (which
// would also stop the page from answering) must not pass for a clean quit.
const port = 8795;
test.use({ baseURL: `http://127.0.0.1:${port}` });

test("Quit asks for confirmation and then ends the server with status 0", async ({ page, request }) => {
  const home = mkdtempSync(join(tmpdir(), "karma-e2e-quit-"));
  const server = spawn(process.env.KARMA_BIN ?? "../.build/release/karma", ["--serve", "--port", String(port)], {
    env: { ...process.env, HOME: home, XDG_DATA_HOME: join(home, ".local/share"), XDG_CONFIG_HOME: join(home, ".config") },
    stdio: "ignore",
  });
  const exited = once(server, "exit");

  try {
    const headers = { "X-Karma-Client": "web" };
    await expect
      .poll(async () => (await request.get("/api/app/info", { headers }).catch(() => null))?.ok() ?? false, {
        timeout: 20_000,
      })
      .toBe(true);

    await openFixture(page);
    await pickMenuItem(page, "Karma Pro", "Quit Karma Pro");
    const alert = page.getByRole("alertdialog");
    await expect(alert).toBeVisible();

    await alert.getByRole("button", { name: "Cancel" }).click();
    await expect(alert).toBeHidden();
    expect((await request.get("/api/app/info", { headers })).ok()).toBe(true);

    await pickMenuItem(page, "Karma Pro", "Quit Karma Pro");
    await alert.getByRole("button", { name: "Quit" }).click();
    const [code] = await exited;
    expect(code).toBe(0);
  } finally {
    server.kill();
  }
});
