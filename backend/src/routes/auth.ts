import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { query } from '../db.js';
import { authenticate, type DecodedIdToken } from '../auth.js';

/**
 * POST /auth/verify
 * Body: none (just the Bearer header).
 * Verifies the Firebase ID token, upserts the users row (email, display_name,
 * photo_url from the decoded token), and returns the user + coupleId (if paired).
 *
 * POST /auth/fcm-token
 * Body: { token: string }
 * Appends the FCM token to users.fcm_tokens (dedup). Returns 200.
 */
export const authRoutes: FastifyPluginAsync = async (app) => {
  app.post('/auth/verify', async (request: FastifyRequest, reply: FastifyReply) => {
    let decoded: DecodedIdToken;
    try {
      decoded = await authenticate(request);
    } catch (err) {
      const statusCode = (err as { statusCode?: number }).statusCode ?? 401;
      return reply.code(statusCode).send({
        error: 'unauthorized',
        message: err instanceof Error ? err.message : 'Unauthorized',
      });
    }

    const user = await upsertUser(decoded);
    return reply.code(200).send({ user });
  });

  app.post('/auth/fcm-token', async (request: FastifyRequest, reply: FastifyReply) => {
    let decoded: DecodedIdToken;
    try {
      decoded = await authenticate(request);
    } catch (err) {
      const statusCode = (err as { statusCode?: number }).statusCode ?? 401;
      return reply.code(statusCode).send({
        error: 'unauthorized',
        message: err instanceof Error ? err.message : 'Unauthorized',
      });
    }

    const body = request.body as { token?: unknown } | null;
    const token =
      typeof body?.token === 'string' ? body.token.trim() : '';
    if (!token) {
      return reply.code(400).send({ error: 'bad_request', message: 'Missing "token" in body' });
    }

    await addFcmToken(decoded.uid, token);
    return reply.code(200).send({ ok: true });
  });
};

/**
 * Insert the user if new, refresh email/display_name/photo_url if existing.
 * Returns the stored row (uid, email, display_name, photo_url, couple_id).
 *
 * ON CONFLICT ... DO UPDATE ensures email/photo/etc. stay in sync across
 * re-logins while preserving couple_id and fcm_tokens (which are managed by
 * other flows).
 */
export async function upsertUser(decoded: DecodedTokenInput): Promise<UserRow> {
  const now = Date.now();
  const res = await query<UserRow>(
    `INSERT INTO users (uid, email, display_name, photo_url, created_at)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (uid) DO UPDATE
       SET email = EXCLUDED.email,
           display_name = EXCLUDED.display_name,
           photo_url = EXCLUDED.photo_url
     RETURNING uid, email, display_name, photo_url, couple_id`,
    [decoded.uid, decoded.email ?? null, decoded.name ?? null, decoded.picture ?? null, now]
  );
  return res.rows[0];
}

export async function addFcmToken(uid: string, token: string): Promise<void> {
  // Remove the token if already present (dedup), then append it once.
  await query(
    `UPDATE users
       SET fcm_tokens = array_remove(fcm_tokens, $2) || ARRAY[$2]
     WHERE uid = $1`,
    [uid, token]
  );
}

export interface UserRow {
  uid: string;
  email: string;
  display_name: string | null;
  photo_url: string | null;
  couple_id: string | null;
}

// Avoid an import cycle: this is just DecodedIdToken, but we accept a
// structural type so tests can pass a plain object without importing the
// firebase-coupled type.
type DecodedTokenInput = {
  uid: string;
  email?: string;
  name?: string;
  picture?: string;
};

export default authRoutes;
