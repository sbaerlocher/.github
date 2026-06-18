import path from "node:path";
import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

// Org template: Vitest "projects" split for a Cloudflare Astro/Worker app.
//
// Two projects run side by side:
//   - unit        — fast, runs in a DOM-ish env, no Worker runtime. Pure logic
//                   under src/lib (or wherever your testable code lives).
//   - integration — runs the BUILT worker inside Miniflare via the Cloudflare
//                   vitest pool, with a mock-upstream worker standing in for
//                   any outbound service binding.
//
// Adopt: copy this dir's files, then adjust the marked spots below. Most apps
// only touch (1) the unit `plugins`/`environment`/`setupFiles`, (2) the
// outbound service name, and (3) wrangler.test.jsonc.

const mockUpstreamScript = path.resolve("tests/integration/mock-upstream.mjs");

export default defineConfig({
  test: {
    // Root-only knobs (vitest 4 forbids these per-project) ───────────────
    //
    // The integration project loads the built worker, which may compile a
    // WASM module on import (e.g. es-module-lexer in an Astro build). The
    // Workers test sandbox forbids that and surfaces it as an unhandled
    // rejection. The unit project never imports the built worker, so this
    // suppression cannot mask a real unit failure — it only stops the WASM
    // reject from flaking the exit code. Drop it if your build has no WASM.
    dangerouslyIgnoreUnhandledErrors: true,

    coverage: {
      // The vitest-pool-workers runtime cannot do v8 coverage (it needs
      // node:inspector, which workerd only stubs) — the pool throws on
      // `provider: "v8"`. Use istanbul, which instruments at build time and
      // runs anywhere. Install @vitest/coverage-istanbul.
      provider: "istanbul",
      reporter: ["text", "lcov"],
      reportsDirectory: "./coverage",
      // ── adjust: what you actually want covered ──
      include: ["src/lib/**"],
      exclude: ["src/lib/**/__tests__/**", "src/lib/types/**", "src/lib/config.ts"],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },
    },

    projects: [
      {
        // ── adjust: framework plugin + env for your unit tests ──
        // Svelte: plugins: [svelte()]  ·  React: [react()]  ·  none: drop it.
        plugins: [],
        test: {
          name: "unit",
          include: ["src/**/*.test.ts"],
          // happy-dom is lighter than jsdom; use "node" if no DOM needed.
          environment: "happy-dom",
          // ── adjust or drop if you have no global test setup ──
          setupFiles: ["./src/test-setup.ts"],
        },
      },
      {
        test: {
          name: "integration",
          include: ["tests/integration/**/*.test.ts"],
        },
        plugins: [
          cloudflareTest({
            wrangler: { configPath: "./wrangler.test.jsonc" },
            miniflare: {
              // ── adjust: the binding name your worker calls outbound ──
              // Must match the `services[].service` in wrangler.test.jsonc and
              // the worker `name` below. Drop this whole block if your worker
              // has no outbound service binding to mock.
              outboundService: "mock-upstream",
              workers: [
                {
                  name: "mock-upstream",
                  modules: true,
                  modulesRoot: path.resolve("."),
                  scriptPath: mockUpstreamScript,
                  // ── adjust: keep in sync with your prod compat settings ──
                  compatibilityDate: "2026-05-13",
                  compatibilityFlags: ["nodejs_compat"],
                  // Toggle mock behaviour from a test via env (see mock-upstream).
                  bindings: { MODE: "ok" },
                },
              ],
            },
          }),
        ],
      },
    ],
  },
});
