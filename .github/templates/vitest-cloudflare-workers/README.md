# Vitest Projects Template — Cloudflare Astro/Worker

Org template for testing a Cloudflare Worker (typically an Astro SSR app) with
two Vitest **projects** in one config:

| Project       | Runs                                   | Speed | What it catches                          |
| ------------- | -------------------------------------- | ----- | ---------------------------------------- |
| `unit`        | plain logic in a DOM-ish env, no Worker | fast  | pure functions, components, lib code     |
| `integration` | the **built** worker inside Miniflare  | slow  | routing, rendering, service bindings     |

The integration project loads the real build output and serves any outbound
service binding from a **mock upstream worker**, so the worker is exercised
end-to-end without hitting a live backend.

Extracted from `sbaerlocher/sbaerlo.ch`.

## Files

```text
vitest.config.ts                      # the two-project setup (unit + integration)
wrangler.test.jsonc                   # test-only wrangler config, fake ids, mock service
tests/env.d.ts                        # types for exports.default + Cloudflare.Env
tests/integration/mock-upstream.mjs   # mock for the outbound service binding
tests/integration/example.test.ts     # integration test skeleton
```

Unit tests stay co-located with source (`src/**/*.test.ts`).

## Adopt

1. Copy the files above into the repo root (keep the `tests/` layout).
2. Install dev deps:

   ```bash
   pnpm add -D vitest @vitest/coverage-v8 @cloudflare/vitest-pool-workers happy-dom
   ```

   Reference versions (sbaerlo.ch, 2026-06): `vitest@4`,
   `@cloudflare/vitest-pool-workers@0.16`, `happy-dom@20`. Match your prod
   `wrangler` major.

3. Add scripts to `package.json`:

   ```jsonc
   {
     "test": "vitest run --project unit",
     "test:unit": "vitest run --project unit",
     "test:integration": "vitest run --project integration",
     "test:watch": "vitest --project unit",
     "test:coverage": "vitest run --coverage"
   }
   ```

4. Walk the `── adjust ──` markers in `vitest.config.ts` and
   `wrangler.test.jsonc`:
   - unit project: framework plugin (`svelte()`/`react()`/none), `environment`,
     `setupFiles`, coverage `include`/`exclude`.
   - integration: outbound service name (must match across `vitest.config.ts`
     `outboundService`, the mock worker `name`, and `wrangler.test.jsonc`
     `services[].service`), `compatibility_date`/`flags` (mirror prod).
   - `wrangler.test.jsonc`: `name`, `main`, bindings — same shape as prod
     `wrangler.jsonc` with fake ids.
   - `mock-upstream.mjs`: the path it matches and the fixtures it returns.

5. Replace `example.test.ts` with real assertions.

## Notes

- **No outbound service?** Drop the `outboundService`/`workers` block in
  `vitest.config.ts`, the `services` array in `wrangler.test.jsonc`, and the
  mock file. The integration project still runs the built worker.
- **`dangerouslyIgnoreUnhandledErrors`** is only needed when the build compiles
  WASM on import (common with Astro's `es-module-lexer`). Drop it otherwise —
  see the inline comment.
- Root-only knobs in vitest 4: `coverage` and
  `dangerouslyIgnoreUnhandledErrors` cannot be set per-project.
- The integration project needs the worker **built first**
  (`pnpm build`) — `dist/` must exist before `test:integration`.
