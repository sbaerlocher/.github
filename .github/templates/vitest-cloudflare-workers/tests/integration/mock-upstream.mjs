// Mock upstream worker — stands in for whatever service binding your worker
// calls outbound (an API, a GraphQL endpoint, another worker). The integration
// project routes the worker's outbound fetches here via `outboundService`.
//
// Pattern:
//   - Match on the request shape (path + payload), not on incidental details
//     like an operation name, so refactors don't silently break the mock.
//   - Drive variant responses (ok / empty / fail) from an env binding (MODE)
//     so a single test can flip behaviour without a second mock file.
//
// Replace the body below with your own fixtures and matching logic.

const fixture = {
  message: "hello from the mock upstream",
  items: [
    { id: "1", title: "First" },
    { id: "2", title: "Second" },
  ],
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // ── adjust: the path(s) your worker actually calls ──
    if (url.pathname !== "/api/data") {
      return new Response("not found", { status: 404 });
    }

    // MODE comes from `bindings.MODE` in vitest.config.ts. Override per test by
    // re-running the worker with a different binding, or branch on a header.
    const mode = env.MODE ?? "ok";
    if (mode === "fail") {
      return new Response("upstream error", { status: 500 });
    }

    return Response.json({
      ...fixture,
      items: mode === "empty" ? [] : fixture.items,
    });
  },
};
