import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { authenticate, type DecodedIdToken } from '../auth.js';
import { query } from '../db.js';
import { ForbiddenError, NotFoundError, getCoupleOr404 } from '../couples.js';
import { sendToCouple } from './sync.js';

/**
 * User REST routes — V3.
 *
 * Wire shape (Flutter `UserModel.fromJson`): camelCase keys
 *   { uid, email, displayName, photoUrl, timezone, coupleId,
 *     fcmTokens, createdAt, showLateNightWindows }
 *
 * DB columns (snake_case): uid, email, display_name, photo_url, timezone,
 *   couple_id, fcm_tokens, show_late_night_windows, created_at
 */

interface UserRow {
  uid: string;
  email: string;
  display_name: string | null;
  photo_url: string | null;
  timezone: string;
  couple_id: string | null;
  fcm_tokens: string[];
  show_late_night_windows: boolean;
  created_at: number;
}

function rowToJson(row: UserRow, includeFcm: boolean) {
  const out: Record<string, unknown> = {
    uid: row.uid,
    email: row.email,
    displayName: row.display_name,
    photoUrl: row.photo_url,
    timezone: row.timezone,
    coupleId: row.couple_id,
    createdAt: row.created_at,
    showLateNightWindows: row.show_late_night_windows,
  };
  if (includeFcm) out.fcmTokens = row.fcm_tokens;
  return out;
}

async function getUid(request: FastifyRequest): Promise<string> {
  const attached = (request as any).user as DecodedIdToken | undefined;
  if (attached?.uid) return attached.uid;
  return (await authenticate(request)).uid;
}

function sendError(reply: FastifyReply, err: unknown) {
  const statusCode = (err as { statusCode?: number }).statusCode ?? 500;
  return reply.code(statusCode).send({
    error:
      statusCode === 400
        ? 'bad_request'
        : statusCode === 403
          ? 'forbidden'
          : statusCode === 404
            ? 'not_found'
            : 'error',
    message: err instanceof Error ? err.message : 'Internal error',
  });
}

async function loadUser(uid: string): Promise<UserRow | null> {
  const res = await query<UserRow>(
    'SELECT uid, email, display_name, photo_url, timezone, couple_id, fcm_tokens, show_late_night_windows, created_at FROM users WHERE uid = $1',
    [uid]
  );
  return res.rows.length === 0 ? null : res.rows[0];
}

/**
 * Authorise the caller to read `targetUid`:
 *  - the user themselves, OR
 *  - their partner (a couple member).
 * Resolves to the caller's uid (for the self path) so handlers can branch.
 */
async function assertCanReadUser(targetUid: string, callerUid: string): Promise<void> {
  if (targetUid === callerUid) return;
  const target = await loadUser(targetUid);
  if (!target) throw new NotFoundError('User not found');
  const coupleId = target.couple_id;
  if (!coupleId) throw new ForbiddenError('Not authorised to view this user');
  // Throws 403 if the caller isn't a member of the couple.
  const couple = await getCoupleOr404(coupleId);
  if (couple.user_a_uid !== callerUid && couple.user_b_uid !== callerUid) {
    throw new ForbiddenError('Not authorised to view this user');
  }
}

export const userRoutes: FastifyPluginAsync = async (app) => {
  // GET /users/me — the caller's own full profile (incl. fcmTokens).
  app.get('/users/me', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const row = await loadUser(uid);
    if (!row) {
      return reply.code(404).send({ error: 'not_found', message: 'User not found' });
    }
    return reply.code(200).send(rowToJson(row, true));
  });

  // GET /users/:uid — a user's profile (self or partner). fcmTokens omitted
  // (the partner does not need them).
  app.get('/users/:uid', async (request: FastifyRequest, reply: FastifyReply) => {
    let callerUid: string;
    try {
      callerUid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const { uid } = request.params as { uid: string };
    try {
      await assertCanReadUser(uid, callerUid);
    } catch (err) {
      return sendError(reply, err);
    }
    const row = await loadUser(uid);
    if (!row) {
      return reply.code(404).send({ error: 'not_found', message: 'User not found' });
    }
    return reply.code(200).send(rowToJson(row, uid === callerUid));
  });

  // PATCH /users/:uid — partial self-update (timezone, showLateNightWindows,
  // displayName). Only the user themselves may patch. Broadcasts user:update
  // to their couple so the partner's overlap controller re-computes.
  app.patch('/users/:uid', async (request: FastifyRequest, reply: FastifyReply) => {
    let callerUid: string;
    try {
      callerUid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const { uid } = request.params as { uid: string };
    if (uid !== callerUid) {
      return sendError(reply, new ForbiddenError('Cannot patch another user'));
    }
    const body = (request.body as Record<string, unknown> | null) ?? {};

    const sets: string[] = [];
    const params: unknown[] = [];
    if (body.timezone !== undefined) {
      if (typeof body.timezone !== 'string' || body.timezone.length === 0) {
        return reply.code(400).send({ error: 'bad_request', message: 'Invalid "timezone"' });
      }
      params.push(body.timezone);
      sets.push(`timezone = $${params.length}`);
    }
    if (body.showLateNightWindows !== undefined) {
      if (typeof body.showLateNightWindows !== 'boolean') {
        return reply.code(400).send({ error: 'bad_request', message: 'Invalid "showLateNightWindows"' });
      }
      params.push(body.showLateNightWindows);
      sets.push(`show_late_night_windows = $${params.length}`);
    }
    if (body.displayName !== undefined) {
      if (typeof body.displayName !== 'string') {
        return reply.code(400).send({ error: 'bad_request', message: 'Invalid "displayName"' });
      }
      params.push(body.displayName.length === 0 ? null : body.displayName);
      sets.push(`display_name = $${params.length}`);
    }
    if (sets.length === 0) {
      return reply.code(400).send({ error: 'bad_request', message: 'No updatable fields in body' });
    }
    params.push(uid);
    const res = await query<UserRow>(
      `UPDATE users SET ${sets.join(', ')} WHERE uid = $${params.length}
       RETURNING uid, email, display_name, photo_url, timezone, couple_id, fcm_tokens, show_late_night_windows, created_at`,
      params
    );
    if (res.rows.length === 0) {
      return reply.code(404).send({ error: 'not_found', message: 'User not found' });
    }
    const row = res.rows[0];
    const json = rowToJson(row, true);
    if (row.couple_id) {
      sendToCouple(row.couple_id, { t: 'user:update', user: json }, callerUid);
    }
    return reply.code(200).send(json);
  });
};

export default userRoutes;
