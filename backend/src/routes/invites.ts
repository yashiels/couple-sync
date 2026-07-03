import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import crypto from 'node:crypto';
import { authenticate, type DecodedIdToken } from '../auth.js';
import { query, getPool } from '../db.js';
import { sendToUid } from './sync.js';

/**
 * Invite REST routes — V4 (pairing lifecycle).
 *
 * Port of functions/src/redeemInvite.ts. Two endpoints:
 *   POST /invites             — mint a 6-char alphanumeric code, 48h expiry
 *   POST /invites/:code/redeem — atomic pairing in a single Postgres tx
 *
 * Wire shape (camelCase): { code, expiresAt } / { coupleId }
 */

// 48 hours in ms.
const INVITE_TTL_MS = 48 * 60 * 60 * 1000;
// Unambiguous alphabet: no 0/O/1/I/L to avoid manual-entry confusion.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_LEN = 6;

class BadRequestError extends Error {
  statusCode = 400 as const;
  constructor(message: string) {
    super(message);
    this.name = 'BadRequestError';
  }
}

class NotFoundError extends Error {
  statusCode = 404 as const;
  constructor(message: string) {
    super(message);
    this.name = 'NotFoundError';
  }
}

class ConflictError extends Error {
  statusCode = 409 as const;
  constructor(message: string) {
    super(message);
    this.name = 'ConflictError';
  }
}

class GoneError extends Error {
  statusCode = 410 as const;
  constructor(message: string) {
    super(message);
    this.name = 'GoneError';
  }
}

function genCode(): string {
  const bytes = crypto.randomBytes(CODE_LEN);
  let out = '';
  for (let i = 0; i < CODE_LEN; i++) {
    out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  }
  return out;
}

async function getUid(request: FastifyRequest): Promise<string> {
  const attached = (request as any).user as DecodedIdToken | undefined;
  if (attached?.uid) return attached.uid;
  return (await authenticate(request)).uid;
}

function sendError(reply: FastifyReply, err: unknown) {
  const statusCode = (err as { statusCode?: number }).statusCode ?? 500;
  const label =
    statusCode === 400 ? 'bad_request'
    : statusCode === 404 ? 'not_found'
    : statusCode === 409 ? 'conflict'
    : statusCode === 410 ? 'gone'
    : 'error';
  return reply.code(statusCode).send({
    error: label,
    message: err instanceof Error ? err.message : 'Internal error',
  });
}

export const inviteRoutes: FastifyPluginAsync = async (app) => {
  // POST /invites — mint a fresh code. Body may be empty; createdByUid comes
  // from the authed token. Collisions on the 6-char PK are astronomically
  // unlikely (~30 bits), but ON CONFLICT DO NOTHING + a retry loop covers it.
  app.post('/invites', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const now = Date.now();
    const expiresAt = now + INVITE_TTL_MS;

    let code: string | null = null;
    for (let attempt = 0; attempt < 5; attempt++) {
      const candidate = genCode();
      try {
        await query(
          'INSERT INTO invites (code, created_by_uid, expires_at, status, created_at) VALUES ($1, $2, $3, $4, $5) ON CONFLICT (code) DO NOTHING',
          [candidate, uid, expiresAt, 'pending', now]
        );
        // ON CONFLICT DO NOTHING still "succeeds" (row 0). Verify it's ours by
        // reading back — only the winning insert will match our created_by_uid
        // + created_at. Cheap and bulletproof.
        const check = await query<{ code: string }>(
          'SELECT code FROM invites WHERE code = $1 AND created_by_uid = $2 AND created_at = $3',
          [candidate, uid, now]
        );
        if (check.rows.length > 0) {
          code = candidate;
          break;
        }
      } catch (err) {
        return sendError(reply, err);
      }
    }
    if (!code) {
      return reply.code(500).send({ error: 'error', message: 'Could not generate unique invite code' });
    }
    return reply.code(201).send({ code, expiresAt });
  });

  // POST /invites/:code/redeem — atomic pairing.
  app.post('/invites/:code/redeem', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const { code } = request.params as { code: string };
    if (!code || typeof code !== 'string') {
      return sendError(reply, new BadRequestError('Invite code is required'));
    }

    const pool = getPool();
    const client = await pool.connect();
    let coupleId: string | null = null;
    let inviterUid: string | null = null;
    try {
      await client.query('BEGIN');

      // Lock the invite row for the duration of the tx. Two concurrent
      // redeemers on the same code serialize here; the second sees the
      // committed 'redeemed' status and takes the idempotent branch.
      const inviteRes = await client.query<{
        code: string;
        created_by_uid: string;
        couple_id: string | null;
        expires_at: number;
        status: string;
      }>(
        'SELECT code, created_by_uid, couple_id, expires_at, status FROM invites WHERE code = $1 FOR UPDATE',
        [code]
      );
      if (inviteRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return sendError(reply, new NotFoundError('Invite code not found'));
      }
      const invite = inviteRes.rows[0];

      if (invite.status === 'redeemed' && invite.couple_id) {
        // Idempotent: this code was already redeemed. Scope the coupleId
        // leak to the two legitimate parties (inviter + original redeemer).
        // Any other caller probing a redeemed code gets 409 with no coupleId.
        const coupleRes = await client.query<{ user_a_uid: string; user_b_uid: string }>(
          'SELECT user_a_uid, user_b_uid FROM couples WHERE id = $1',
          [invite.couple_id]
        );
        const coupleRow = coupleRes.rows[0];
        const inviter = invite.created_by_uid;
        const redeemer = coupleRow
          ? (coupleRow.user_a_uid === inviter ? coupleRow.user_b_uid : coupleRow.user_a_uid)
          : null;
        if (uid !== inviter && uid !== redeemer) {
          await client.query('ROLLBACK');
          return reply.code(409).send({
            error: 'conflict',
            message: 'Invite has already been redeemed',
          });
        }
        coupleId = invite.couple_id;
        inviterUid = inviter;
        await client.query('COMMIT');
      } else if (invite.status === 'expired' || Date.now() > invite.expires_at) {
        await client.query('ROLLBACK');
        return sendError(reply, new GoneError('Invite has expired'));
      } else if (invite.status !== 'pending') {
        // Any other non-pending status (defensive — shouldn't happen).
        await client.query('ROLLBACK');
        return sendError(reply, new ConflictError(`Invite is not redeemable (status: ${invite.status})`));
      } else if (invite.created_by_uid === uid) {
        await client.query('ROLLBACK');
        return sendError(reply, new BadRequestError('Cannot redeem your own invite code'));
      } else {
        // Happy path: create the couple, stamp the invite, link both users.
        inviterUid = invite.created_by_uid;
        coupleId = crypto.randomUUID();
        const now = Date.now();
        await client.query(
          'INSERT INTO couples (id, user_a_uid, user_b_uid, status, paired_at, created_at, unpair_history) VALUES ($1, $2, $3, $4, $5, $6, $7)',
          [coupleId, inviterUid, uid, 'active', now, now, JSON.stringify([])]
        );
        await client.query(
          'UPDATE invites SET status = $1, couple_id = $2 WHERE code = $3',
          ['redeemed', coupleId, code]
        );
        await client.query('UPDATE users SET couple_id = $1 WHERE uid = $2', [coupleId, inviterUid]);
        await client.query('UPDATE users SET couple_id = $1 WHERE uid = $2', [coupleId, uid]);
        await client.query('COMMIT');
      }
    } catch (err) {
      try { await client.query('ROLLBACK'); } catch { /* swallow */ }
      return sendError(reply, err);
    } finally {
      client.release();
    }

    // At this point coupleId/inviterUid are non-null (every non-returning
    // branch of the tx sets them). The early-return branches already exited.
    const cId = coupleId as string;
    const invUid = inviterUid as string;

    // Post-commit WS broadcast to both partners (best-effort). The in-memory
    // coupleMembers map is NOT updated here — it's rebuilt on each WS connect
    // from the users table, so the next (re)connect picks up the new pairing.
    // sendToUid targets the socket directly regardless of couple membership.
    sendToUid(invUid, { t: 'pairing', coupleId: cId, partnerUid: uid });
    sendToUid(uid, { t: 'pairing', coupleId: cId, partnerUid: invUid });

    return reply.code(200).send({ coupleId: cId });
  });
};

export default inviteRoutes;
