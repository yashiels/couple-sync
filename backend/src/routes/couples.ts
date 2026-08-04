import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../auth.js';
import { assertMember } from '../couples.js';
import { withTx } from '../db.js';
import { HttpError } from '../http.js';
import { sendTo } from '../sockets.js';
import type { CoupleRow } from '../wire.js';

export default async function couplesRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth);

  app.get('/couples/:id', async (req) => {
    const { id } = req.params as { id: string };
    return { couple: await assertMember(id, req.uid) };
  });

  app.post('/couples/:id/unpair', async (req) => {
    const { id } = req.params as { id: string };

    const couple = await withTx(async (c) => {
      // The same advisory lock refreshOverlap takes, and it must be the first statement. Without
      // it a refresh already mid-compute can upsert overlaps_latest after the DELETE below and
      // resurrect the row for a couple that no longer exists — invisible until someone wonders why
      // unpairing did not stick.
      await c.query('SELECT pg_advisory_xact_lock(hashtext($1))', [id]);

      // Membership is re-checked here rather than via assertMember above the transaction: under the
      // lock, so a second concurrent unpair sees 'inactive' and cannot run this body twice.
      const [row] = await c.query<CoupleRow>('SELECT * FROM couples WHERE id = $1', [id]);
      if (!row || row.status !== 'active') throw new HttpError(403, 'forbidden');
      if (row.user_a_uid !== req.uid && row.user_b_uid !== req.uid) {
        throw new HttpError(403, 'forbidden');
      }

      await c.query(`UPDATE couples SET status = 'inactive' WHERE id = $1`, [id]);
      // By uid off the couple row, not `WHERE couple_id = $1`: a stale users.couple_id would
      // otherwise leave a user pointing at a dead couple.
      await c.query('UPDATE users SET couple_id = NULL WHERE uid IN ($1, $2)', [
        row.user_a_uid,
        row.user_b_uid,
      ]);
      await c.query('DELETE FROM timeblocks WHERE couple_id = $1', [id]);
      await c.query('DELETE FROM overlaps_latest WHERE couple_id = $1', [id]);
      return row;
    });

    for (const uid of [couple.user_a_uid, couple.user_b_uid]) {
      sendTo(uid, { t: 'unpair', couple_id: id });
    }
    return { ok: true };
  });
}
