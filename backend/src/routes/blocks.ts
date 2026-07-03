import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import crypto from 'node:crypto';
import { authenticate, type DecodedIdToken } from '../auth.js';
import { query, getPool } from '../db.js';
import { assertMember, ForbiddenError } from '../couples.js';
import { sendToCouple } from './sync.js';

/**
 * Block REST routes — V3.
 *
 * JSON shape (Flutter `TimeBlock.toJson`): camelCase keys
 *   { id, coupleId, userId, title, type, category, startUtc, endUtc,
 *     timezone, recurrenceRule?, source, visibility, createdAt }
 *
 * DB columns (snake_case): id, couple_id, user_id, title, type, category,
 *   start_utc, end_utc, timezone, recurrence_rule, source, visibility,
 *   created_at
 *
 * The mapping is done at this boundary so the rest of the backend speaks
 * snake_case (the DB) and the wire speaks camelCase (the Flutter client).
 */

interface BlockRow {
  id: string;
  couple_id: string;
  user_id: string;
  title: string;
  type: string;
  category: string | null;
  start_utc: number;
  end_utc: number;
  timezone: string;
  recurrence_rule: string | null;
  source: string;
  visibility: string;
  created_at: number;
}

interface BlockJson {
  id: string;
  coupleId: string;
  userId: string;
  title: string;
  type: string;
  category: string | null;
  startUtc: number;
  endUtc: number;
  timezone: string;
  recurrenceRule: string | null;
  source: string;
  visibility: string;
  createdAt: number;
}

function rowToJson(row: BlockRow): BlockJson {
  return {
    id: row.id,
    coupleId: row.couple_id,
    userId: row.user_id,
    title: row.title,
    type: row.type,
    category: row.category,
    startUtc: row.start_utc,
    endUtc: row.end_utc,
    timezone: row.timezone,
    recurrenceRule: row.recurrence_rule,
    source: row.source,
    visibility: row.visibility,
    createdAt: row.created_at,
  };
}

/** Required fields for a create (the Flutter `TimeBlock.toJson()` surface). */
interface BlockInput {
  coupleId?: unknown;
  userId?: unknown;
  title?: unknown;
  type?: unknown;
  category?: unknown;
  startUtc?: unknown;
  endUtc?: unknown;
  timezone?: unknown;
  recurrenceRule?: unknown;
  source?: unknown;
  visibility?: unknown;
  createdAt?: unknown;
}

function readString(v: unknown, field: string): string {
  if (typeof v !== 'string' || v.length === 0) {
    throw new BadRequestError(`Missing or invalid "${field}"`);
  }
  return v;
}

function readOptString(v: unknown): string | null {
  if (v == null) return null;
  if (typeof v !== 'string') return null;
  return v.length === 0 ? null : v;
}

function readInt(v: unknown, field: string): number {
  if (typeof v !== 'number' || !Number.isFinite(v) || !Number.isInteger(v)) {
    throw new BadRequestError(`Missing or invalid "${field}" (expected integer)`);
  }
  return v;
}

class BadRequestError extends Error {
  statusCode = 400 as const;
  constructor(message: string) {
    super(message);
    this.name = 'BadRequestError';
  }
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
    error: statusCode === 400 ? 'bad_request' : statusCode === 403 ? 'forbidden' : 'error',
    message: err instanceof Error ? err.message : 'Internal error',
  });
}

function broadcastBlockSet(coupleId: string, block: BlockJson, excludeUid: string) {
  sendToCouple(coupleId, { t: 'block:set', block }, excludeUid);
}

function broadcastBlockDel(coupleId: string, id: string, excludeUid: string) {
  sendToCouple(coupleId, { t: 'block:del', id }, excludeUid);
}

export const blockRoutes: FastifyPluginAsync = async (app) => {
  // GET /blocks?coupleId=X — all blocks for the couple (both partners).
  app.get('/blocks', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const coupleId = (request.query as { coupleId?: string } | undefined)?.coupleId;
    if (!coupleId) {
      return reply.code(400).send({ error: 'bad_request', message: 'Missing coupleId query param' });
    }
    try {
      await assertMember(coupleId, uid);
    } catch (err) {
      return sendError(reply, err);
    }
    const res = await query<BlockRow>(
      'SELECT id, couple_id, user_id, title, type, category, start_utc, end_utc, timezone, recurrence_rule, source, visibility, created_at FROM timeblocks WHERE couple_id = $1 ORDER BY start_utc ASC',
      [coupleId]
    );
    return reply.code(200).send({ blocks: res.rows.map(rowToJson) });
  });

  // POST /blocks — create + broadcast block:set to the partner.
  app.post('/blocks', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const body = (request.body as BlockInput | null) ?? {};
    let coupleId: string;
    try {
      coupleId = readString(body.coupleId, 'coupleId');
      const userId = readString(body.userId, 'userId');
      const title = readString(body.title, 'title');
      const type = readString(body.type, 'type');
      const category = readOptString(body.category);
      const startUtc = readInt(body.startUtc, 'startUtc');
      const endUtc = readInt(body.endUtc, 'endUtc');
      const timezone = readString(body.timezone, 'timezone');
      const recurrenceRule = readOptString(body.recurrenceRule);
      const source = readString(body.source, 'source');
      const visibility = readString(body.visibility, 'visibility');
      const createdAt =
        typeof body.createdAt === 'number' && Number.isFinite(body.createdAt)
          ? body.createdAt
          : Date.now();

      await assertMember(coupleId, uid);

      const id = crypto.randomUUID();
      const res = await query<BlockRow>(
        `INSERT INTO timeblocks
           (id, couple_id, user_id, title, type, category, start_utc, end_utc, timezone, recurrence_rule, source, visibility, created_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
         RETURNING id, couple_id, user_id, title, type, category, start_utc, end_utc, timezone, recurrence_rule, source, visibility, created_at`,
        [id, coupleId, userId, title, type, category, startUtc, endUtc, timezone, recurrenceRule, source, visibility, createdAt]
      );
      const block = rowToJson(res.rows[0]);
      broadcastBlockSet(coupleId, block, uid);
      return reply.code(201).send(block);
    } catch (err) {
      return sendError(reply, err);
    }
  });

  // GET /blocks/:id — single block (requires coupleId query param for auth).
  app.get('/blocks/:id', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const { id } = request.params as { id: string };
    const coupleId = (request.query as { coupleId?: string } | undefined)?.coupleId;
    if (!coupleId) {
      return reply.code(400).send({ error: 'bad_request', message: 'Missing coupleId query param' });
    }
    try {
      await assertMember(coupleId, uid);
    } catch (err) {
      return sendError(reply, err);
    }
    const res = await query<BlockRow>(
      'SELECT id, couple_id, user_id, title, type, category, start_utc, end_utc, timezone, recurrence_rule, source, visibility, created_at FROM timeblocks WHERE id = $1 AND couple_id = $2',
      [id, coupleId]
    );
    if (res.rows.length === 0) {
      return reply.code(404).send({ error: 'not_found', message: 'Block not found' });
    }
    return reply.code(200).send(rowToJson(res.rows[0]));
  });

  // PUT /blocks/:id — partial update + broadcast block:set with the full block.
  app.put('/blocks/:id', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const { id } = request.params as { id: string };
    const body = (request.body as Record<string, unknown> | null) ?? {};

    // First load the block to get its couple_id for the membership check.
    const existing = await query<{ couple_id: string }>(
      'SELECT couple_id FROM timeblocks WHERE id = $1',
      [id]
    );
    if (existing.rows.length === 0) {
      return reply.code(404).send({ error: 'not_found', message: 'Block not found' });
    }
    const coupleId = existing.rows[0].couple_id;
    try {
      await assertMember(coupleId, uid);
    } catch (err) {
      return sendError(reply, err);
    }

    // Build a SET clause from the allowed partial fields.
    const sets: string[] = [];
    const params: unknown[] = [];
    const push = (col: string, jsonKey: string, transform: (v: unknown) => unknown = (v) => v) => {
      if (body[jsonKey] !== undefined) {
        params.push(transform(body[jsonKey]));
        sets.push(`${col} = $${params.length}`);
      }
    };
    push('user_id', 'userId');
    push('title', 'title');
    push('type', 'type');
    push('category', 'category');
    push('start_utc', 'startUtc');
    push('end_utc', 'endUtc');
    push('timezone', 'timezone');
    push('recurrence_rule', 'recurrenceRule');
    push('source', 'source');
    push('visibility', 'visibility');

    if (sets.length === 0) {
      return reply.code(400).send({ error: 'bad_request', message: 'No updatable fields in body' });
    }
    params.push(id);
    const res = await query<BlockRow>(
      `UPDATE timeblocks SET ${sets.join(', ')} WHERE id = $${params.length}
       RETURNING id, couple_id, user_id, title, type, category, start_utc, end_utc, timezone, recurrence_rule, source, visibility, created_at`,
      params
    );
    const block = rowToJson(res.rows[0]);
    broadcastBlockSet(coupleId, block, uid);
    return reply.code(200).send(block);
  });

  // DELETE /blocks/:id — delete + broadcast block:del.
  app.delete('/blocks/:id', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const { id } = request.params as { id: string };

    const existing = await query<{ couple_id: string }>(
      'SELECT couple_id FROM timeblocks WHERE id = $1',
      [id]
    );
    if (existing.rows.length === 0) {
      // Idempotent-ish: 404 mirrors the Flutter expectation (getBlock returns null).
      return reply.code(404).send({ error: 'not_found', message: 'Block not found' });
    }
    const coupleId = existing.rows[0].couple_id;
    try {
      await assertMember(coupleId, uid);
    } catch (err) {
      return sendError(reply, err);
    }
    await query('DELETE FROM timeblocks WHERE id = $1', [id]);
    broadcastBlockDel(coupleId, id, uid);
    return reply.code(200).send({ ok: true, id });
  });

  // POST /blocks/batch — atomic replace of google-sourced blocks for a user.
  app.post('/blocks/batch', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const body = request.body as {
      coupleId?: unknown;
      userId?: unknown;
      source?: unknown;
      blocks?: unknown;
    } | null;

    let coupleId: string;
    try {
      coupleId = readString(body?.coupleId, 'coupleId');
    } catch (err) {
      return sendError(reply, err);
    }
    const userId = readString(body?.userId, 'userId');
    const source = typeof body?.source === 'string' && body.source.length > 0 ? body.source : 'google';
    const blocksIn = Array.isArray(body?.blocks) ? (body!.blocks as BlockInput[]) : [];

    try {
      await assertMember(coupleId, uid);
    } catch (err) {
      return sendError(reply, err);
    }

    // The caller must be replacing their own google blocks (not their
    // partner's). The Flutter SyncService only ever calls this with the
    // caller's own uid, but enforce it server-side.
    if (userId !== uid) {
      return sendError(reply, new ForbiddenError('Cannot replace another user\'s blocks'));
    }

    // Parse + validate each incoming block (before opening the tx).
    const toInsert: {
      id: string;
      userId: string;
      title: string;
      type: string;
      category: string | null;
      startUtc: number;
      endUtc: number;
      timezone: string;
      recurrenceRule: string | null;
      source: string;
      visibility: string;
      createdAt: number;
    }[] = [];
    try {
      for (const b of blocksIn) {
        toInsert.push({
          id: crypto.randomUUID(),
          userId,
          title: readString(b.title, 'title'),
          type: readString(b.type, 'type'),
          category: readOptString(b.category),
          startUtc: readInt(b.startUtc, 'startUtc'),
          endUtc: readInt(b.endUtc, 'endUtc'),
          timezone: readString(b.timezone, 'timezone'),
          recurrenceRule: readOptString(b.recurrenceRule),
          source,
          visibility: readString(b.visibility, 'visibility'),
          createdAt:
            typeof b.createdAt === 'number' && Number.isFinite(b.createdAt)
              ? b.createdAt
              : Date.now(),
        });
      }
    } catch (err) {
      return sendError(reply, err);
    }

    const pool = getPool();
    const client = await pool.connect();
    let deletedIds: string[] = [];
    let createdBlocks: BlockJson[] = [];
    try {
      await client.query('BEGIN');
      const delRes = await client.query<{ id: string }>(
        'DELETE FROM timeblocks WHERE couple_id = $1 AND user_id = $2 AND source = $3 RETURNING id',
        [coupleId, userId, source]
      );
      deletedIds = delRes.rows.map((r) => r.id);

      for (const b of toInsert) {
        const res = await client.query<BlockRow>(
          `INSERT INTO timeblocks
             (id, couple_id, user_id, title, type, category, start_utc, end_utc, timezone, recurrence_rule, source, visibility, created_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
           RETURNING id, couple_id, user_id, title, type, category, start_utc, end_utc, timezone, recurrence_rule, source, visibility, created_at`,
          [b.id, coupleId, b.userId, b.title, b.type, b.category, b.startUtc, b.endUtc, b.timezone, b.recurrenceRule, b.source, b.visibility, b.createdAt]
        );
        createdBlocks.push(rowToJson(res.rows[0]));
      }
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      client.release();
      return sendError(reply, err);
    }
    client.release();

    // Broadcast outside the tx (best-effort; the DB is the source of truth
    // and the client re-syncs on reconnect).
    for (const id of deletedIds) broadcastBlockDel(coupleId, id, uid);
    for (const block of createdBlocks) broadcastBlockSet(coupleId, block, uid);

    return reply.code(200).send({
      deletedCount: deletedIds.length,
      createdCount: createdBlocks.length,
    });
  });
};

export default blockRoutes;
