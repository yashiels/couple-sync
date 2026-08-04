import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../auth.js';
import { query } from '../db.js';
import { bad, HttpError } from '../http.js';
import type { UserRow } from '../wire.js';

function tokenFromBody(body: unknown): string {
  const { token } = (body ?? {}) as { token?: unknown };
  if (typeof token !== 'string' || !token.trim()) throw bad('bad_token');
  return token.trim();
}

/** Every route here is self-only by construction: the uid comes from the verified ID token. */
export default async function authRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth);

  // Upsert on every sign-in. The DO UPDATE list is exactly the three fields Firebase owns:
  // timezone, couple_id, created_at and both preference columns are ours and must survive a
  // re-sign-in, or confirming a timezone would be undone by the next app launch.
  app.post('/auth/verify', async (req) => {
    const c = req.claims;
    const [user] = await query<UserRow>(
      `INSERT INTO users (uid, email, display_name, photo_url, created_at)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (uid) DO UPDATE SET
         email = EXCLUDED.email,
         display_name = COALESCE(EXCLUDED.display_name, users.display_name),
         photo_url = COALESCE(EXCLUDED.photo_url, users.photo_url)
       RETURNING *`,
      [req.uid, c.email ?? '', c.name ?? null, c.picture ?? null, Date.now()],
    );
    if (!user) throw new HttpError(500, 'internal');
    // The caller's own row, so fcm_tokens stay on it.
    return { user };
  });

  app.post('/auth/fcm-token', async (req) => {
    const token = tokenFromBody(req.body);
    // Dedup in SQL, so a repeat registration is a no-op and a second device still gets its own row
    // entry — the array is per user, not per device.
    const [user] = await query<UserRow>(
      `UPDATE users
          SET fcm_tokens = CASE WHEN $2 = ANY(fcm_tokens) THEN fcm_tokens
                                ELSE array_append(fcm_tokens, $2) END
        WHERE uid = $1
        RETURNING *`,
      [req.uid, token],
    );
    if (!user) throw new HttpError(404, 'unknown_user');
    return { fcm_tokens: user.fcm_tokens };
  });

  // Called on sign-out, so a shared handset never keeps the previous user's token and start pushing
  // one person's free time to another. Removing a token the user does not have is a no-op, not an
  // error, and the user's other devices keep theirs.
  app.delete('/auth/fcm-token', async (req) => {
    const token = tokenFromBody(req.body);
    const [user] = await query<UserRow>(
      `UPDATE users
          SET fcm_tokens = ARRAY(SELECT t FROM unnest(fcm_tokens) AS t WHERE t <> $2)
        WHERE uid = $1
        RETURNING *`,
      [req.uid, token],
    );
    if (!user) throw new HttpError(404, 'unknown_user');
    return { fcm_tokens: user.fcm_tokens };
  });
}
