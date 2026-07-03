import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { authenticate, type DecodedIdToken } from '../auth.js';
import { assertMember, ForbiddenError, type CoupleRow } from '../couples.js';
import { getPool } from '../db.js';
import { sendToUid } from './sync.js';

/**
 * Couple REST routes — V3.
 *
 * Wire shape (Flutter `CoupleModel.fromJson`): camelCase keys
 *   { userAUid, userBUid, status, pairedAt, unpairHistory, createdAt }
 */

function rowToJson(row: CoupleRow) {
  return {
    id: row.id,
    userAUid: row.user_a_uid,
    userBUid: row.user_b_uid,
    status: row.status,
    pairedAt: row.paired_at,
    unpairHistory: row.unpair_history,
    createdAt: row.created_at,
  };
}

async function getUid(request: FastifyRequest): Promise<string> {
  const attached = (request as any).user as DecodedIdToken | undefined;
  if (attached?.uid) return attached.uid;
  return (await authenticate(request)).uid;
}

function sendError(reply: FastifyReply, err: unknown) {
  const statusCode = (err as { statusCode?: number }).statusCode ?? 500;
  return reply.code(statusCode).send({
    error: statusCode === 403 ? 'forbidden' : statusCode === 404 ? 'not_found' : 'error',
    message: err instanceof Error ? err.message : 'Internal error',
  });
}

export const coupleRoutes: FastifyPluginAsync = async (app) => {
  // GET /couples/:id — return the couple doc. Membership enforced.
  app.get('/couples/:id', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const { id } = request.params as { id: string };
    try {
      const couple = await assertMember(id, uid);
      return reply.code(200).send(rowToJson(couple));
    } catch (err) {
      return sendError(reply, err);
    }
  });

  // POST /couples/:id/unpair — port of functions/src/unpairCouple.ts.
  // In one tx: assert caller is a member; if already inactive, idempotent
  // (still clear the caller's stale couple_id); else set couples.status=
  // 'inactive', append {at, reason} to unpair_history, clear couple_id on
  // both users, and delete the couple's timeblocks + overlaps_latest
  // (matches the CF's recursiveDelete of timeblocks + overlaps windows).
  app.post('/couples/:id/unpair', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const { id } = request.params as { id: string };

    const pool = getPool();
    const client = await pool.connect();
    let partnerUid: string | null = null;
    let didBroadcast = false;
    try {
      await client.query('BEGIN');

      // Lock the couple row so two concurrent unpair attempts serialize.
      const coupleRes = await client.query<CoupleRow>(
        'SELECT id, user_a_uid, user_b_uid, status, paired_at, created_at, unpair_history FROM couples WHERE id = $1 FOR UPDATE',
        [id]
      );
      if (coupleRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return sendError(reply, new ForbiddenError('Not a member of this couple'));
      }
      const couple = coupleRes.rows[0];
      if (couple.user_a_uid !== uid && couple.user_b_uid !== uid) {
        await client.query('ROLLBACK');
        return sendError(reply, new ForbiddenError('Not a member of this couple'));
      }
      partnerUid = couple.user_a_uid === uid ? couple.user_b_uid : couple.user_a_uid;

      if (couple.status === 'inactive') {
        // Idempotent: already unpaired. Clear the caller's stale couple_id
        // so they can re-pair. (Partner's couple_id was cleared on the
        // original unpair; leave it alone here.) Do NOT rebroadcast — the
        // partner was already notified on the original unpair.
        await client.query('UPDATE users SET couple_id = NULL WHERE uid = $1', [uid]);
        await client.query('COMMIT');
        return reply.code(200).send({ coupleId: id, idempotent: true });
      }

      const now = Date.now();
      const entry = { at: now, reason: 'manual_unpair' };
      // JSONB || merges arrays (appends to unpair_history, preserving prior entries).
      await client.query(
        'UPDATE couples SET status = $1, unpair_history = unpair_history || $2::jsonb WHERE id = $3',
        ['inactive', JSON.stringify([entry]), id]
      );
      await client.query('UPDATE users SET couple_id = NULL WHERE uid IN ($1, $2)', [uid, partnerUid]);
      // Match the CF's recursiveDelete: drop shared timeblocks + cached overlap.
      await client.query('DELETE FROM timeblocks WHERE couple_id = $1', [id]);
      await client.query('DELETE FROM overlaps_latest WHERE couple_id = $1', [id]);
      await client.query('COMMIT');
      didBroadcast = true;
    } catch (err) {
      try { await client.query('ROLLBACK'); } catch { /* swallow */ }
      return sendError(reply, err);
    } finally {
      client.release();
    }

    // Post-commit WS broadcast to both partners (best-effort), only on the
    // active→inactive transition (not the idempotent re-unpair).
    if (didBroadcast) {
      sendToUid(uid, { t: 'unpair', coupleId: id });
      if (partnerUid && partnerUid !== uid) {
        sendToUid(partnerUid, { t: 'unpair', coupleId: id });
      }
    }

    return reply.code(200).send({ coupleId: id });
  });
};

export default coupleRoutes;
