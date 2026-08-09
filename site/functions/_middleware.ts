// One hostname, two backends: the static 1-pager serves marketing/support/legal pages, and every
// API path proxies through this function to the Fastify backend on the Atlas Cloudflare Tunnel.
//
// The route list below is the ONLY thing that decides "page or API". Keep it in sync with
// backend/src (the Fastify route registrations). A path that matches a page route never reaches the
// tunnel; a path that matches an API route is forwarded untouched.
//
// API_BASE_URL is the tunnel hostname (e.g. https://couple-sync-tunnel.yashiel.dev). It is a
// build-time env var, not a secret.

interface Env {
  API_BASE_URL: string;
}

// Exact paths that belong to the API. Everything else falls through to static assets.
const API_EXACT: ReadonlySet<string> = new Set([
  '/health',
  '/sync', // WebSocket upgrade
  '/auth/verify',
  '/auth/fcm-token',
  '/users/me',
  '/invites',
  '/blocks',
  '/blocks/google',
  '/overlaps/latest',
  '/admin/cleanup',
]);

// Dynamic API routes: a prefix that is still one resource. Each must not swallow a same-named page.
// /invites/:code/redeem is deliberately absent here — a bare /invites/<code> is not a live route,
// so that one is disambiguated by the /redeem suffix in isApiPath below.
const API_PREFIX = [
  '/users/', // /users/:uid
  '/couples/', // /couples/:id, /couples/:id/unpair
  '/blocks/', // /blocks/:id
  '/overlaps/', // (reserved; today only /overlaps/latest, matched exactly above)
] as const;

// Exported for the unit test; the routing decision must be verifiable without standing up Pages.
export function isApiPath(pathname: string): boolean {
  if (API_EXACT.has(pathname)) return true;
  if (API_PREFIX.some((p) => pathname.startsWith(p))) return true;
  // Only the /redeem suffix is a live API path under /invites/.
  if (pathname.startsWith('/invites/')) return pathname.endsWith('/redeem');
  return false;
}

export const onRequest: PagesFunction<Env> = async ({ request, env, next }) => {
  const url = new URL(request.url);
  if (!isApiPath(url.pathname)) return next(); // static asset

  const target = new URL(url.pathname + url.search, env.API_BASE_URL);
  // Passing the original Request preserves the method, headers (Authorization), body, and the
  // WebSocket Upgrade headers on /sync — fetch() in a Worker transparently passes 101 through.
  return fetch(new Request(target.toString(), request));
};
