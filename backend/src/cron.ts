import type { FastifyInstance, FastifyRequest } from 'fastify';
import { createHash, timingSafeEqual } from 'node:crypto';
import { deleteAccount, reconcilePendingDeletions } from './account.js';
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
 * Shared ADMIN_TOKEN gate for the admin routes. 503 (not 401) when unset means the endpoint is
 * disabled, not that the caller got it wrong. The token rides its own `x-admin-token` header, never
 * Authorization — every other route reads a Firebase ID token from there, and one header meaning two
 * credentials is how a route ends up accepting either. An empty/absent header runs the same fixed-width
 * comparison as a wrong one.
 */
function assertAdmin(req: FastifyRequest): void {
  if (EXPECTED === null) throw new HttpError(503, 'admin_disabled');
  const supplied = req.headers['x-admin-token'];
  if (typeof supplied !== 'string' || !timingSafeEqual(digest(supplied), EXPECTED)) {
    throw new HttpError(401, 'unauthorized');
  }
}

/**
 * Admin routes. Registered on the instance rather than added to index.ts's `routePlugins`, because they
 * are guarded by ADMIN_TOKEN instead of requireAuth — guards.matrix.test.ts excludes them by name and
 * cron.test.ts covers them instead.
 */
export function registerAdminRoutes(app: FastifyInstance): void {
  app.post('/admin/cleanup', async (req) => {
    assertAdmin(req);
    return { expired: await expireStaleInvites() };
  });

  // Operator fulfillment of a verified web deletion request (§B1): the public delete page cannot
  // self-authenticate, so an operator who has verified the requester owns the account email runs this.
  // Resolves email -> uid, then the same deleteAccount() the self-serve route uses.
  app.post('/admin/delete-account', async (req) => {
    assertAdmin(req);
    const { email, uid } = (req.body ?? {}) as { email?: unknown; uid?: unknown };
    const suppliedUid = typeof uid === 'string' && uid.trim() ? uid.trim() : null;
    const suppliedEmail = typeof email === 'string' && email.trim() ? email.trim() : null;
    if ((suppliedUid === null) === (suppliedEmail === null)) {
      throw new HttpError(400, 'exactly_one_identifier_required');
    }

    let target: string | null = null;
    if (suppliedUid) {
      const [row] = await query<{ uid: string }>(
        `SELECT uid FROM users WHERE uid = $1
         UNION
         SELECT uid FROM deleted_accounts WHERE uid = $1
         LIMIT 1`,
        [suppliedUid],
      );
      target = row?.uid ?? null;
    } else if (suppliedEmail) {
      const [row] = await query<{ uid: string }>('SELECT uid FROM users WHERE email = $1', [
        suppliedEmail,
      ]);
      target = row?.uid ?? null;
    }
    if (!target) throw new HttpError(404, 'unknown_user');
    await deleteAccount(target);
    return { deleted: target };
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
    // Every tick, not just at 03:00: finish any account deletion that committed in Postgres but whose
    // Firebase Auth delete did not complete (a crash between the two). Cheap and idempotent — the
    // partial-index query returns nothing in the common case — and mandatory, because until it runs the
    // /auth/verify tombstone lock keeps the user out while their Firebase Auth record still exists.
    void reconcilePendingDeletions().catch((err: unknown) => {
      console.error('[cron] deletion reconcile failed', err);
    });

    const now = new Date();
    const day = now.toISOString().slice(0, 10);
    if (now.getUTCHours() !== 3 || day === lastRun) return;
    lastRun = day;
    void expireStaleInvites().catch((err: unknown) => {
      console.error('[cron] invite expiry failed', err);
    });
  }, TICK_MS);
}
