/// <reference types="@cloudflare/vitest-pool-workers/types" />

declare namespace Cloudflare {
  interface Env {
    // ── adjust: the vars/bindings your worker reads, mirrored from wrangler ──
    UPSTREAM_ENDPOINT: string;
  }

  // Make `exports.default` from `cloudflare:workers` resolve to the loopback
  // Fetcher for your default-exported handler. Without this, `Cloudflare.Exports`
  // is `{}` and `exports.default` is a type error. Augments the empty
  // `GlobalProps` declared by `@cloudflare/workers-types`.
  interface GlobalProps {
    mainModule: { default: ExportedHandler<Cloudflare.Env> };
  }
}
