import type { FastifyInstance } from 'fastify';
import { createHash, timingSafeEqual } from 'node:crypto';
import { config } from './config.js';
import { query } from './db.js';
import { HttpError } from './http.js';

const digest = (s: string) => createHash('sha256').update(s).digest(); // always 32 bytes

/**
 * Precomputed ONCE at module load, for two reasons. timingSafeEqual throws RangeError on a length
 * mismatch, so both sides have to be fixed width or a wrong-length token becomes a 500 that leaks
 * the expected length; and hashing the secret per request would make request duration depend on the
 * secret's length, which is the very leak timingSafeEqual exists to close.
 */
const EXPECTED = config.adminToken ? digest(config.adminToken) : null;

/** Rows affected. Idempotent: re-running it flips nothing that is already expired. */
export async function expireStaleInvites(): Promise<number> {
  const rows = await query<{ code: string }>(
    `UPDATE invites SET status = 'expired'
      WHERE status = 'pending' AND expires_at < $1
      RETURNING code`,
    [Date.now()],
  );
  return rows.length;
}

/**
 * POST /admin/cleanup. Registered on the instance rather than added to index.ts's `routePlugins`,
 * because it is guarded by ADMIN_TOKEN instead of requireAuth — guards.matrix.test.ts excludes it by
 * name and cron.test.ts covers it instead.
 */
export function registerAdminRoutes(app: FastifyInstance): void {
  app.post('/admin/cleanup', async (req) => {
    // 503, not 401: an unset token means the endpoint is disabled, not that the caller got it wrong.
    if (EXPECTED === null) throw new HttpError(503, 'admin_disabled');
    // Its own header, not Authorization: every other route reads a Firebase ID token from there, and
    // one header that means two different credentials is how a route ends up accepting either.
    const supplied = req.headers['x-admin-token'];
    // An empty or absent header goes through the same fixed-width comparison as a wrong one.
    if (typeof supplied !== 'string' || !timingSafeEqual(digest(supplied), EXPECTED)) {
      throw new HttpError(401, 'unauthorized');
    }
    return { expired: await expireStaleInvites() };
  });
}

/** 15 minutes: fine enough to hit the 03:00 UTC hour, coarse enough to cost nothing. */
const TICK_MS = 15 * 60_000;

/**
 * Daily 03:00 UTC invite sweep. A clock check on a plain interval, not node-cron — one daily job is
 * not worth a dependency.
 *
 * Ceiling: the interval drifts on a long-running process, and the sweep fires only on whichever
 * replica owns this timer, so with more than one replica it runs N times or, after a restart during
 * the 03:00 hour, not at all that day. Both are harmless because the sweep is idempotent and every
 * read path re-checks `expires_at` anyway (routes/invites.ts). Upgrade path if that ever stops being
 * true: a real scheduler, or leader election on a Postgres advisory lock.
 */
export function startInviteExpiryTimer(): NodeJS.Timeout {
  let lastRun = '';
  return setInterval(() => {
    const now = new Date();
    const day = now.toISOString().slice(0, 10);
    if (now.getUTCHours() !== 3 || day === lastRun) return;
    lastRun = day;
    void expireStaleInvites().catch((err: unknown) => {
      console.error('[cron] invite expiry failed', err);
    });
  }, TICK_MS);
}
