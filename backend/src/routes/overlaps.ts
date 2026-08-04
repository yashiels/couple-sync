import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../auth.js';
import { assertMember } from '../couples.js';
import { bad } from '../http.js';
import { refreshOverlap } from '../overlapService.js';

export default async function overlapsRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth);

  /**
   * The read path is also the staleness fix (§3): refreshOverlap recomputes the hash for the current
   * hour bucket and only writes when it moved, so windows never rot as `now` advances and no cron is
   * needed. A couple that has never computed therefore computes and upserts here — two block-less
   * partners legitimately have ~15 windows, so an empty response would be a lie.
   */
  app.get('/overlaps/latest', async (req) => {
    const { coupleId } = (req.query ?? {}) as { coupleId?: unknown };
    if (typeof coupleId !== 'string' || !coupleId) throw bad('couple_id_required');
    await assertMember(coupleId, req.uid);

    // req.uid, never null: triggeredBy is excluded from the push fan-out, and passing null would FCM
    // a reader who has no live socket about a recompute their own pull-to-refresh caused.
    const { windows, computedAt } = await refreshOverlap(coupleId, req.uid, req.log);
    return { couple_id: coupleId, windows, computed_at: computedAt };
  });
}
