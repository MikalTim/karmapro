import { expect, test } from "@playwright/test";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// On Linux UserDefaults lives in memory until it is written. The MCP access token is created the first time the
// settings are read (a GET), so no write request follows it; stopping the server with SIGTERM or Ctrl+C must still
// leave it on disk, or a client configured from the Settings window stops working after a restart.

const port = 8796;
const headers = { "X-Karma-Client": "web" };

function startServer(home: string) {
  return spawn(process.env.KARMA_BIN ?? "../.build/release/karma", ["--serve", "--port", String(port)], {
    env: { ...process.env, HOME: home, XDG_DATA_HOME: join(home, ".local/share"), XDG_CONFIG_HOME: join(home, ".config") },
    stdio: "ignore",
  });
}

test("a setting created by a read survives SIGTERM and shows on the next start", async ({ request }) => {
  const home = mkdtempSync(join(tmpdir(), "karma-e2e-restart-"));
  const base = `http://127.0.0.1:${port}`;
  const waitUntilUp = () =>
    expect
      .poll(async () => (await request.get(`${base}/api/app/info`, { headers }).catch(() => null))?.ok() ?? false, {
        timeout: 20_000,
      })
      .toBe(true);

  const first = startServer(home);
  const firstExit = once(first, "exit");
  let token: string | undefined;
  try {
    await waitUntilUp();
    const state: { url: string } = await (await request.get(`${base}/api/mcp`, { headers })).json();
    token = state.url.split("/").pop();
    expect(token).toMatch(/^[0-9a-f]+$/);
    first.kill("SIGTERM");
    const [code] = await firstExit;
    expect(code).toBe(0);
  } finally {
    first.kill();
  }

  const second = startServer(home);
  try {
    await waitUntilUp();
    const state: { url: string } = await (await request.get(`${base}/api/mcp`, { headers })).json();
    expect(state.url.split("/").pop()).toBe(token);
  } finally {
    second.kill();
  }
});
