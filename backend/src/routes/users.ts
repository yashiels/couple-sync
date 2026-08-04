import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../auth.js';
import { assertMember, partnerUid } from '../couples.js';
import { query } from '../db.js';
import { bad, HttpError } from '../http.js';
import { refreshOverlap } from '../overlapService.js';
import { sendTo } from '../sockets.js';
import { isValidTimezone } from '../tz.js';
import { stripTokens, type CoupleRow, type UserRow } from '../wire.js';

async function load(uid: string): Promise<UserRow> {
  const [row] = await query<UserRow>('SELECT * FROM users WHERE uid = $1', [uid]);
  if (!row) throw new HttpError(404, 'unknown_user');
  return row;
}

/**
 * The only patchable columns. An allow-list, not a deny-list: email, couple_id, fcm_tokens,
 * created_at and uid are all server-owned, and a deny-list grows a hole every time a column lands.
 * Each entry validates its own value and returns the error code for a bad one.
 */
const FIELDS: Record<string, (value: unknown) => string | null> = {
  // null is rejected separately: clearing a confirmed timezone would drop the user back into
  // onboarding and leave the overlap engine without a zone for a live couple.
  timezone: (v) =>
    v === null ? 'timezone_required' : isValidTimezone(v) ? null : 'invalid_timezone',
  display_name: (v) => (v === null || typeof v === 'string' ? null : 'invalid_display_name'),
  show_late_night_windows: (v) =>
    typeof v === 'boolean' ? null : 'invalid_show_late_night_windows',
  notifications_enabled: (v) => (typeof v === 'boolean' ? null : 'invalid_notifications_enabled'),
};

export default async function usersRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth);

  // The caller's own row, so fcm_tokens stay on it.
  app.get('/users/me', async (req) => ({ user: await load(req.uid) }));

  app.get('/users/:uid', async (req) => {
    const { uid } = req.params as { uid: string };
    const me = await load(req.uid);
    if (uid === me.uid) return { user: me };
    if (!me.couple_id) throw new HttpError(403, 'forbidden');
    // assertMember answers 403 for a dead couple too, so nothing here leaks whether uid exists.
    const couple = await assertMember(me.couple_id, me.uid);
    if (partnerUid(couple, me.uid) !== uid) throw new HttpError(403, 'forbidden');
    return { user: stripTokens(await load(uid)) };
  });

  app.patch('/users/:uid', async (req) => {
    const { uid } = req.params as { uid: string };
    if (uid !== req.uid) throw new HttpError(403, 'forbidden');

    const patch = (req.body ?? {}) as Record<string, unknown>;
    const sets: string[] = [];
    const params: unknown[] = [req.uid];
    for (const [key, value] of Object.entries(patch)) {
      const validate = Object.hasOwn(FIELDS, key) ? FIELDS[key] : undefined;
      if (!validate) throw bad('unknown_field', key);
      const problem = validate(value);
      if (problem) throw bad(problem, key);
      params.push(value);
      // Interpolating `key` is safe and stays safe: anything not in FIELDS threw above.
      sets.push(`${key} = $${params.length}`);
    }
    if (sets.length === 0) throw bad('empty_patch');

    const [user] = await query<UserRow>(
      `UPDATE users SET ${sets.join(', ')} WHERE uid = $1 RETURNING *`,
      params,
    );
    if (!user) throw new HttpError(404, 'unknown_user');

    if (user.couple_id) {
      const [couple] = await query<CoupleRow>(
        `SELECT * FROM couples WHERE id = $1 AND status = 'active'`,
        [user.couple_id],
      );
      // No couple row means unpaired mid-flight: nobody to tell, nothing to recompute.
      if (couple) {
        sendTo(partnerUid(couple, user.uid), { t: 'user:update', user: stripTokens(user) });
        // Keyed on presence, not on a value diff: refreshOverlap dedups on input_hash, so a patch
        // that set the same timezone again costs one compute and no write, WS or push.
        if ('timezone' in patch || 'show_late_night_windows' in patch) {
          await refreshOverlap(user.couple_id, user.uid, req.log);
        }
      }
    }
    return { user };
  });
}
