import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../auth.js';
import { query } from '../db.js';
import { bad } from '../http.js';
import type { UserRow } from '../wire.js';

export default async function authRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth);

  // Upsert on every sign-in. Never clobbers timezone / couple_id / prefs — only the identity fields
  // Firebase owns.
  app.post('/auth/verify', async (req) => {
    const c = req.claims;
    const [row] = await query<UserRow>(
      `INSERT INTO users (uid, email, display_name, photo_url, created_at)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (uid) DO UPDATE SET
         email = EXCLUDED.email,
         display_name = COALESCE(EXCLUDED.display_name, users.display_name),
         photo_url = COALESCE(EXCLUDED.photo_url, users.photo_url)
       RETURNING *`,
      [req.uid, c.email ?? '', c.name ?? null, c.picture ?? null, Date.now()],
    );
    // The caller's own row, so fcm_tokens stay on it. Task 6 rewrites this route.
    return { user: row! };
  });

  app.post('/auth/fcm-token', async (req) => {
    const { token } = (req.body ?? {}) as { token?: unknown };
    if (typeof token !== 'string' || !token.trim()) throw bad('bad_token');
    const [row] = await query<UserRow>(
      `UPDATE users
         SET fcm_tokens = CASE WHEN $2 = ANY(fcm_tokens) THEN fcm_tokens
                               ELSE array_append(fcm_tokens, $2) END
       WHERE uid = $1
       RETURNING *`,
      [req.uid, token.trim()],
    );
    if (!row) throw bad('unknown_user');
    return { fcmTokens: row.fcm_tokens };
  });
}
