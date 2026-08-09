# Couple Sync — website

The 1-pager at `https://couple-sync.yashiel.dev`, deployed to **Cloudflare Pages**. It shares the
hostname with the API: Pages serves the static pages, and a Pages Function proxies the API paths to
the Fastify backend on the Atlas Cloudflare Tunnel.

## Layout

| Path | What |
|---|---|
| `public/` | The static site — `index.html`, `privacy/`, `support/`, `invite/`, `style.css`. No build step. |
| `public/_redirects` | Maps `/invite/<code>` → the invite page (Pages runs this after functions). |
| `public/_headers` | Light security headers on the static pages. |
| `functions/_middleware.ts` | The page-vs-API split. API paths proxy to the tunnel; everything else serves static assets. |
| `functions/_middleware.test.ts` | Pins every live Fastify route to the correct side of the split. |

## The routing rule

`functions/_middleware.ts` holds the single source of truth for which paths are API. It must stay
in sync with `backend/src` (the Fastify route registrations). The test enumerates every live route
and asserts it lands on the API side — if you add a backend route, add it to `API_EXACT` or
`API_PREFIX` and to the test.

`/invite/<code>` is a **page**, not an API path: the code is shown for manual entry and deep-linked
via `couplesync://invite/<code>`. There is deliberately no public "look up this invite" endpoint —
that would leak inviter identity on an enumerable 6-char code.

## Deploy

CI deploys on push to `main` when `site/**` changes (`.github/workflows/site-deploy.yml`). Manual:

```bash
cd site
pnpm install
pnpm deploy            # wrangler pages deploy public --project-name couple-sync
```

Two pieces of config live outside the repo:

- **`CF_PAGES_API_TOKEN`** (GitHub secret) — a Cloudflare API token scoped to Pages:Edit on this
  project only. Not the broad account token.
- **`API_BASE_URL`** (Pages project env var) — the tunnel hostname the proxy forwards to, e.g.
  `https://couple-sync-tunnel.yashiel.dev`. Set it in the Pages project settings.

## Test

The routing test runs with the app suite from the repo root (`npm test`); `vitest.config.ts`
includes `site/**/*.test.ts`. To run it alone:

```bash
npx vitest run --config /tmp/vitest.site.mjs --root .
```

where `/tmp/vitest.site.mjs` is any config whose `test.include` covers `site/**/*.test.ts` (the
root config already does — this is only for running the file in isolation).
