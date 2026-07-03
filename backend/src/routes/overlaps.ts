import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { authenticate, type DecodedIdToken } from '../auth.js';
import { assertMember } from '../couples.js';
import { query } from '../db.js';

/**
 * Overlap REST routes — V8.
 *
 * The device computes overlap and publishes it over WS (V5); the server stores
 * `overlaps_latest` (dedup via `inputHash`). This route exposes the stored row
 * so a client reconnecting after being offline can fetch the latest overlap
 * without waiting for the partner to recompute + republish (spec §6, §9).
 *
 * Wire shape (Flutter `OverlapResult.fromJson`): camelCase keys
 *   { windows: [{startUtc,endUtc,durationMinutes,score,reasonableBoth}, ...],
 *     computedAt: int (ms since epoch), inputHash: string, computedBy: string? }
 *
 * DB columns (snake_case): couple_id, windows (JSONB), computed_at (BIGINT),
 *   input_hash (TEXT), computed_by (TEXT).
 */

interface OverlapRow {
  couple_id: string;
  windows: unknown;
  computed_at: number;
  input_hash: string;
  computed_by: string | null;
}

interface OverlapJson {
  windows: unknown;
  computedAt: number;
  inputHash: string;
  computedBy: string | null;
}

function rowToJson(row: OverlapRow): OverlapJson {
  return {
    windows: row.windows,
    computedAt: row.computed_at,
    inputHash: row.input_hash,
    computedBy: row.computed_by,
  };
}

/** Pull the decoded uid from the request, or run authenticate (for tests that don't pre-hook). */
async function getUid(request: FastifyRequest): Promise<string> {
  const attached = (request as any).user as DecodedIdToken | undefined;
  if (attached?.uid) return attached.uid;
  return (await authenticate(request)).uid;
}

function sendError(reply: FastifyReply, err: unknown) {
  const statusCode = (err as { statusCode?: number }).statusCode ?? 500;
  return reply.code(statusCode).send({
    error:
      statusCode === 403
        ? 'forbidden'
        : statusCode === 404
          ? 'not_found'
          : statusCode === 400
            ? 'bad_request'
            : 'error',
    message: err instanceof Error ? err.message : 'Internal error',
  });
}

export const overlapRoutes: FastifyPluginAsync = async (app) => {
  // GET /overlaps/latest?coupleId=X — the stored latest overlap for the couple.
  // Bearer-authed; membership enforced via assertMember. Returns 404 if no row
  // exists yet (the Flutter `getOverlap` maps 404 → null).
  app.get('/overlaps/latest', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const coupleId = (request.query as { coupleId?: string } | undefined)?.coupleId;
    if (!coupleId) {
      return reply
        .code(400)
        .send({ error: 'bad_request', message: 'Missing coupleId query param' });
    }
    try {
      await assertMember(coupleId, uid);
    } catch (err) {
      return sendError(reply, err);
    }
    const res = await query<OverlapRow>(
      'SELECT couple_id, windows, computed_at, input_hash, computed_by FROM overlaps_latest WHERE couple_id = $1',
      [coupleId]
    );
    if (res.rows.length === 0) {
      return reply.code(404).send({ error: 'not_found', message: 'No stored overlap for this couple' });
    }
    return reply.code(200).send(rowToJson(res.rows[0]));
  });
};

export default overlapRoutes;
