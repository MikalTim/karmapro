import { defineConfig } from "vitest/config";
import { svelte } from "@sveltejs/vite-plugin-svelte";

// The dev server proxies /api to a running `karma --serve`. changeOrigin stays
// false so the Host header keeps saying "localhost", which the server's
// DNS-rebinding check requires.
export default defineConfig({
  plugins: [svelte()],
  build: { outDir: "dist", emptyOutDir: true },
  server: {
    proxy: {
      "/api": { target: "http://127.0.0.1:8790", changeOrigin: false },
    },
  },
  test: {
    include: ["src/**/*.test.ts"],
    environment: "node",
  },
});
