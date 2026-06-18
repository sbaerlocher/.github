import { exports } from "cloudflare:workers";
import { describe, expect, test } from "vitest";

// Loopback Fetcher for the worker's default export. `exports.default` is typed
// via tests/env.d.ts. Calls hit the real built worker; its outbound service
// binding is served by tests/integration/mock-upstream.mjs.
const worker = exports.default;

describe("worker — integration", () => {
  test("serves a known route", async () => {
    const res = await worker.fetch("https://example.com/");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toMatch(/text\/html/);
  });

  test("renders data from the mock upstream", async () => {
    const res = await worker.fetch("https://example.com/");
    const html = await res.text();
    // Assert against the fixture in mock-upstream.mjs.
    expect(html).toContain("First");
  });

  test("unknown route 404s", async () => {
    const res = await worker.fetch("https://example.com/does-not-exist");
    expect(res.status).toBe(404);
  });
});
