import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { defineConfig } from "@playwright/test";

const port = 8791;
// A throwaway home keeps the specs away from the real settings, bugs, notes and wiki pages. The runner creates
// it and exports it, so the workers (which load this file again) and the specs see the same folder.
const home = (process.env.KARMA_E2E_HOME ??= mkdtempSync(join(tmpdir(), "karma-e2e-home-")));
const binary = process.env.KARMA_BIN ?? "../.build/release/karma";

export default defineConfig({
  testDir: "./e2e",
  timeout: 60_000,
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    viewport: { width: 1440, height: 900 },
    screenshot: "only-on-failure",
  },
  webServer: {
    command: `${binary} --serve --port ${port}`,
    // Playwright treats 200-403 as "up"; the API answers 403 to a probe without the client header.
    url: `http://127.0.0.1:${port}/api/app/info`,
    reuseExistingServer: false,
    env: { HOME: home, XDG_DATA_HOME: join(home, ".local/share"), XDG_CONFIG_HOME: join(home, ".config") },
    stdout: "pipe",
    stderr: "pipe",
  },
});
