import type { FastifyInstance } from 'fastify';
import { randomInt, randomUUID } from 'node:crypto';
import { requireAuth } from '../auth.js';
import { query, withTx } from '../db.js';
import { HttpError } from '../http.js';
import { refreshOverlap } from '../overlapService.js';
import { sendTo } from '../sockets.js';
import { isValidTimezone } from '../tz.js';

const TTL_MS = 48 * 3_600_000;
// No O, 0, I or 1: the code is read off one screen and typed into another. 32^6 ≈ 1.07e9.
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function newCode(): string {
  let code = '';
  for (let i = 0; i < 6; i++) code += ALPHABET[randomInt(ALPHABET.length)];
  return code;
}

/** Local, not in wire.ts: the app only ever sees `{ code, expires_at }`, never a whole invite row. */
interface InviteRow {
  code: string;
  created_by_uid: string;
  couple_id: string | null;
  expires_at: number;
  status: 'pending' | 'accepted' | 'expired';
  created_at: number;
}

interface LockedUser {
  uid: string;
  couple_id: string | null;
  timezone: string | null;
}

export default async function invitesRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth);

  app.post('/invites', async (req, reply) => {
    const [me] = await query<{ couple_id: string | null }>(
      'SELECT couple_id FROM users WHERE uid = $1',
      [req.uid],
    );
    if (!me) throw new HttpError(404, 'unknown_user');
    if (me.couple_id) throw new HttpError(409, 'already_paired');

    const now = Date.now();
    // Invite rows are kept forever (§2), so codes accumulate and a collision is a matter of when.
    // Retrying is cheaper than the 500 a bare INSERT would produce.
    for (let attempt = 0; attempt < 5; attempt++) {
      const [row] = await query<Pick<InviteRow, 'code' | 'expires_at'>>(
        `INSERT INTO invites (code, created_by_uid, expires_at, status, created_at)
         VALUES ($1, $2, $3, 'pending', $4)
         ON CONFLICT (code) DO NOTHING
         RETURNING code, expires_at`,
        [newCode(), req.uid, now + TTL_MS, now],
      );
      if (row) return reply.code(201).send({ code: row.code, expires_at: row.expires_at });
    }
    throw new HttpError(503, 'code_generation_failed');
  });

  app.post('/invites/:code/redeem', async (req) => {
    // Stored codes are upper-case only, and a typed-in code arrives however the keyboard felt.
    const code = (req.params as { code: string }).code.trim().toUpperCase();
    const uid = req.uid;
    const now = Date.now();

    const { coupleId, inviterUid } = await withTx(async (c) => {
      const [invite] = await c.query<InviteRow>(
        'SELECT * FROM invites WHERE code = $1 FOR UPDATE',
        [code],
      );
      if (!invite) throw new HttpError(404, 'unknown_code');
      if (invite.status === 'accepted') throw new HttpError(409, 'invite_used');
      if (invite.status !== 'pending' || invite.expires_at <= now) {
        throw new HttpError(409, 'invite_expired');
      }
      if (invite.created_by_uid === uid) throw new HttpError(409, 'self_pair');

      // Locking the invite is NOT enough: two different codes created by the same user can redeem
      // concurrently and give that user two active couples. Both user rows are therefore locked
      // too, and `ORDER BY uid` is what stops two crossing redemptions deadlocking on each other.
      const locked = await c.query<LockedUser>(
        'SELECT uid, couple_id, timezone FROM users WHERE uid IN ($1, $2) ORDER BY uid FOR UPDATE',
        [uid, invite.created_by_uid],
      );
      const me = locked.find((u) => u.uid === uid);
      const inviter = locked.find((u) => u.uid === invite.created_by_uid);
      if (!me || !inviter) throw new HttpError(404, 'unknown_user');
      if (me.couple_id) throw new HttpError(409, 'already_paired');
      if (inviter.couple_id) throw new HttpError(409, 'inviter_already_paired');

      // Not something the client can be trusted with. Onboarding gates pairing behind timezone
      // setup, but a direct API call could pair two NULL-timezone users and the refreshOverlap
      // below would then hand the engine an invalid zone.
      for (const u of [inviter, me]) {
        if (!u.timezone) throw new HttpError(409, 'timezone_required');
        if (!isValidTimezone(u.timezone)) throw new HttpError(409, 'invalid_timezone');
      }

      const coupleId = randomUUID();
      // The inviter is A: scoring uses A's timezone (§2), and the two slots are otherwise
      // interchangeable, so pick a rule and keep it.
      await c.query(
        `INSERT INTO couples (id, user_a_uid, user_b_uid, status, paired_at, created_at)
         VALUES ($1, $2, $3, 'active', $4, $4)`,
        [coupleId, inviter.uid, me.uid, now],
      );
      await c.query(`UPDATE invites SET status = 'accepted', couple_id = $1 WHERE code = $2`, [
        coupleId,
        code,
      ]);
      await c.query('UPDATE users SET couple_id = $1 WHERE uid IN ($2, $3)', [
        coupleId,
        inviter.uid,
        me.uid,
      ]);
      return { coupleId, inviterUid: inviter.uid };
    });

    // Post-commit only. Both of these are best-effort: the pairing is already durable, so a dead
    // FCM endpoint or a slow engine must not turn it into a 500 the app reads as "not paired".
    try {
      await refreshOverlap(coupleId, uid, req.log);
    } catch (err) {
      req.log.warn({ err }, 'first overlap after pairing failed');
    }
    // The redeemer learns the couple id from this response; only the inviter needs the nudge.
    sendTo(inviterUid, { t: 'pairing', couple_id: coupleId, partner_uid: uid });
    return { couple_id: coupleId };
  });
}
