import type { FastifyInstance } from 'fastify';
import { randomUUID } from 'node:crypto';
// Default import, not `import { rrulestr }`: rrule ships CJS, and a named import of it fails at
// runtime under node's ESM loader ("Named export 'rrulestr' not found") even though tsc and vitest
// both resolve it. overlap/recurrence.ts still uses the named form and crashes `node dist/index.js`
// on load — same one-line fix there.
import rrule from 'rrule';
import { requireAuth } from '../auth.js';
import { assertMember } from '../couples.js';
import { query, withTx, type Querier } from '../db.js';
import { bad, HttpError } from '../http.js';
import { expandBlock } from '../overlap/index.js';
import { refreshOverlap } from '../overlapService.js';
import { sendTo } from '../sockets.js';
import { isValidTimezone } from '../tz.js';
import {
  scrubBlockForViewer,
  toEngineBlock,
  type BlockRow,
  type BlockWithOccurrences,
  type CoupleRow,
} from '../wire.js';

const { RRule, rrulestr } = rrule;

/** A week view asks for ~7 days. The cap bounds both the expansion work and the response size. */
const MAX_RANGE_MS = 60 * 86_400_000;

/** §5: freebusy carries no titles, so every google block gets the same placeholder. */
const GOOGLE_TITLE = 'Busy';

// Exactly the four the engine supports (§3.2). rrulestr happily parses FREQ=HOURLY and friends.
const SUPPORTED_FREQ = new Set([RRule.YEARLY, RRule.MONTHLY, RRule.WEEKLY, RRule.DAILY]);

const INSERT_SQL = `
  INSERT INTO timeblocks (id, couple_id, user_id, title, type, category, start_utc, end_utc,
                          timezone, recurrence_rule, source, visibility, created_at)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
  RETURNING *`;

const SELECT_ONE_SQL = 'SELECT * FROM timeblocks WHERE id = $1 AND couple_id = $2';

function insertParams(row: BlockRow): unknown[] {
  return [
    row.id,
    row.couple_id,
    row.user_id,
    row.title,
    row.type,
    row.category,
    row.start_utc,
    row.end_utc,
    row.timezone,
    row.recurrence_rule,
    row.source,
    row.visibility,
    row.created_at,
  ];
}

function ruleProblem(value: unknown): string | null {
  if (typeof value !== 'string' || !value.trim()) return 'invalid_recurrence_rule';
  const rule = value.trim();
  // FREQ must be stated explicitly. Without it rrulestr silently defaults to YEARLY, so `BYDAY=MO`
  // parses, passes the SUPPORTED_FREQ check below, and is stored as a rule no client can round-trip
  // through the recurrence picker.
  if (!/(^|;)FREQ=/i.test(rule.replace(/^RRULE:/i, ''))) return 'invalid_recurrence_rule';
  let freq: number;
  try {
    // rrulestr for the reject: it throws on a bogus FREQ or BYDAY where RRule.parseString shrugs.
    // parseString too, because that is the exact call expandBlock will make on every read — nothing
    // may be accepted here that would throw later while rendering a calendar.
    freq = rrulestr(rule).options.freq;
    RRule.parseString(rule.replace(/^RRULE:/i, ''));
  } catch {
    return 'invalid_recurrence_rule';
  }
  return SUPPORTED_FREQ.has(freq) ? null : 'unsupported_recurrence_freq';
}

/**
 * The only client-writable columns, each validating its own value. id, couple_id, user_id, source
 * and created_at are server-owned and are never read from a body — a body carrying user_id or
 * source is ignored rather than 400ed, so a forged one is neutralised instead of turned into a
 * probe for which field names are real.
 */
const FIELDS = {
  title: (v: unknown) => (typeof v === 'string' && v.trim() ? null : 'invalid_title'),
  type: (v: unknown) =>
    v === 'busy' || v === 'free' || v === 'tentative' ? null : 'invalid_type',
  category: (v: unknown) => (v === null || typeof v === 'string' ? null : 'invalid_category'),
  start_utc: (v: unknown) => (Number.isInteger(v) ? null : 'invalid_start_utc'),
  end_utc: (v: unknown) => (Number.isInteger(v) ? null : 'invalid_end_utc'),
  timezone: (v: unknown) => (isValidTimezone(v) ? null : 'invalid_timezone'),
  recurrence_rule: (v: unknown) => (v === null ? null : ruleProblem(v)),
  visibility: (v: unknown) =>
    v === 'bothPartners' || v === 'onlyMe' ? null : 'invalid_visibility',
};
type Field = keyof typeof FIELDS;

/** Validates and returns the value. The cast is sound exactly because FIELDS[key] passed. */
function field<T>(key: Field, value: unknown): T {
  const problem = FIELDS[key](value);
  if (problem) throw bad(problem, key);
  return value as T;
}

// §7 spells the couple id `coupleId` in a query string and `couple_id` in a body (the row spelling).
function coupleIdFromQuery(source: unknown): string {
  const { coupleId } = (source ?? {}) as { coupleId?: unknown };
  if (typeof coupleId !== 'string' || !coupleId) throw bad('couple_id_required');
  return coupleId;
}

function coupleIdFromBody(source: unknown): string {
  const { couple_id: coupleId } = (source ?? {}) as { couple_id?: unknown };
  if (typeof coupleId !== 'string' || !coupleId) throw bad('couple_id_required');
  return coupleId;
}

/** Query-string flavour: a param arrives as a string, and '' must not read as 0. */
function epochMs(value: unknown): number | null {
  if (typeof value !== 'string' || !value.trim()) return null;
  const n = Number(value);
  return Number.isInteger(n) ? n : null;
}

/** Required, and capped: the response carries one occurrence per instance in the range. */
function rangeFromQuery(source: unknown): { from: number; to: number } {
  const q = (source ?? {}) as { from?: unknown; to?: unknown };
  const from = epochMs(q.from);
  const to = epochMs(q.to);
  if (from === null || to === null) throw bad('range_required');
  if (to <= from) throw bad('invalid_range');
  if (to - from > MAX_RANGE_MS) throw bad('range_too_large');
  return { from, to };
}

/**
 * The couple, re-read under its advisory lock — the first statement of every write transaction.
 * assertMember already answered 403 for this caller, but it answered before the lock was held, and
 * unpair takes this same lock: without the re-check a write that lost that race inserts a block
 * after the unpair deleted them all, and the refreshOverlap that follows recreates overlaps_latest
 * for a couple that no longer exists. refreshOverlap re-checks status too; either check alone leaves
 * a window open.
 */
async function lockCouple(c: Querier, coupleId: string, uid: string): Promise<CoupleRow> {
  await c.query('SELECT pg_advisory_xact_lock(hashtext($1))', [coupleId]);
  const [couple] = await c.query<CoupleRow>('SELECT * FROM couples WHERE id = $1', [coupleId]);
  if (!couple || couple.status !== 'active') throw new HttpError(403, 'forbidden');
  if (couple.user_a_uid !== uid && couple.user_b_uid !== uid) throw new HttpError(403, 'forbidden');
  return couple;
}

/** The caller's own block, or 403 — identical for a foreign block and one that does not exist. */
async function ownBlock(c: Querier, id: string, coupleId: string, uid: string): Promise<BlockRow> {
  const [block] = await c.query<BlockRow>(SELECT_ONE_SQL, [id, coupleId]);
  if (!block || block.user_id !== uid) throw new HttpError(403, 'forbidden');
  return block;
}

/**
 * Per recipient, because the scrub is per recipient: one write, and the owner gets their title while
 * the partner gets a nulled one. Scrubbing GET /blocks alone would leak every title over the socket.
 */
function broadcastSet(couple: CoupleRow, block: BlockRow): void {
  for (const uid of [couple.user_a_uid, couple.user_b_uid]) {
    sendTo(uid, { t: 'block:set', block: scrubBlockForViewer(block, uid) });
  }
}

export default async function blocksRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth);

  // Membership is checked before the range is validated, so an unauthorized caller learns nothing
  // about the shape of the API. Same ordering on every route below.
  app.get('/blocks', async (req) => {
    const coupleId = coupleIdFromQuery(req.query);
    await assertMember(coupleId, req.uid);
    const { from, to } = rangeFromQuery(req.query);

    // Every block for the couple, not just those whose start_utc lands inside the range: a recurring
    // block's DTSTART can be years earlier. Fine at tens of blocks per couple; if it ever is not, the
    // upgrade is a materialised occurrence table, not an occurrence-aware WHERE clause.
    const rows = await query<BlockRow>(
      'SELECT * FROM timeblocks WHERE couple_id = $1 ORDER BY start_utc',
      [coupleId],
    );
    return {
      blocks: rows.map((row): BlockWithOccurrences => {
        // Clamped to the requested range, not to the engine's 14-day horizon — this is a calendar
        // view, not an overlap computation. toEngineBlock drops the title, so the scrub below cannot
        // affect the geometry: a partner sees every occurrence, just not what the block is.
        const occurrences = expandBlock(toEngineBlock(row), from, to).map((iv) => ({
          start_utc: iv.start,
          end_utc: iv.end,
        }));
        return { ...scrubBlockForViewer(row, req.uid), occurrences };
      }),
    };
  });

  app.get('/blocks/:id', async (req) => {
    const { id } = req.params as { id: string };
    const coupleId = coupleIdFromQuery(req.query);
    await assertMember(coupleId, req.uid);
    const [block] = await query<BlockRow>(SELECT_ONE_SQL, [id, coupleId]);
    // 403, not 404: the same answer a non-member gets, so a block id under someone else's couple is
    // indistinguishable from one that was never created.
    if (!block) throw new HttpError(403, 'forbidden');
    // The direct exfiltration route if this is forgotten — a partner could read any onlyMe title by id.
    return { block: scrubBlockForViewer(block, req.uid) };
  });

  app.post('/blocks', async (req, reply) => {
    const coupleId = coupleIdFromBody(req.body);
    await assertMember(coupleId, req.uid);
    const body = (req.body ?? {}) as Record<string, unknown>;

    const row: BlockRow = {
      id: randomUUID(),
      couple_id: coupleId,
      user_id: req.uid, // forced: the caller can only ever create their own blocks
      title: field<string>('title', body['title']).trim(),
      type: field<BlockRow['type']>('type', body['type']),
      category: 'category' in body ? field<string | null>('category', body['category']) : null,
      start_utc: field<number>('start_utc', body['start_utc']),
      end_utc: field<number>('end_utc', body['end_utc']),
      timezone: field<string>('timezone', body['timezone']),
      recurrence_rule:
        'recurrence_rule' in body
          ? field<string | null>('recurrence_rule', body['recurrence_rule'])
          : null,
      source: 'manual', // forced: PUT /blocks/google is the only writer of google-sourced blocks
      visibility:
        'visibility' in body
          ? field<BlockRow['visibility']>('visibility', body['visibility'])
          : 'bothPartners',
      created_at: Date.now(),
    };
    if (row.end_utc <= row.start_utc) throw bad('invalid_interval');

    const { couple, block } = await withTx(async (c) => {
      const couple = await lockCouple(c, coupleId, req.uid);
      const [block] = await c.query<BlockRow>(INSERT_SQL, insertParams(row));
      if (!block) throw new HttpError(500, 'internal');
      return { couple, block };
    });

    broadcastSet(couple, block);
    await refreshOverlap(coupleId, req.uid, req.log);
    return reply.code(201).send({ block });
  });

  app.patch('/blocks/:id', async (req) => {
    const { id } = req.params as { id: string };
    const coupleId = coupleIdFromBody(req.body);
    await assertMember(coupleId, req.uid);
    const body = (req.body ?? {}) as Record<string, unknown>;

    const patch: Record<string, unknown> = {};
    const params: unknown[] = [id, coupleId];
    const sets: string[] = [];
    for (const [key, value] of Object.entries(body)) {
      if (key === 'couple_id' || !Object.hasOwn(FIELDS, key)) continue;
      patch[key] = field(key as Field, value);
      params.push(value);
      // Interpolating `key` is safe and stays safe: anything not in FIELDS was skipped above.
      sets.push(`${key} = $${params.length}`);
    }
    if (sets.length === 0) throw bad('empty_patch');

    const { couple, block } = await withTx(async (c) => {
      const couple = await lockCouple(c, coupleId, req.uid);
      const existing = await ownBlock(c, id, coupleId, req.uid);
      // A google block mirrors the user's calendar and PUT /blocks/google is its only writer, so an
      // edit here would silently vanish on the next sync.
      if (existing.source === 'google') throw new HttpError(403, 'read_only_block');
      // Merged, so patching one end is still validated against the stored other end.
      const merged = { ...existing, ...patch } as BlockRow;
      if (merged.end_utc <= merged.start_utc) throw bad('invalid_interval');

      const [block] = await c.query<BlockRow>(
        `UPDATE timeblocks SET ${sets.join(', ')} WHERE id = $1 AND couple_id = $2 RETURNING *`,
        params,
      );
      if (!block) throw new HttpError(500, 'internal');
      return { couple, block };
    });

    broadcastSet(couple, block);
    await refreshOverlap(coupleId, req.uid, req.log);
    return { block };
  });

  app.delete('/blocks/:id', async (req) => {
    const { id } = req.params as { id: string };
    const coupleId = coupleIdFromQuery(req.query);
    await assertMember(coupleId, req.uid);

    const couple = await withTx(async (c) => {
      const couple = await lockCouple(c, coupleId, req.uid);
      await ownBlock(c, id, coupleId, req.uid);
      await c.query('DELETE FROM timeblocks WHERE id = $1', [id]);
      return couple;
    });

    // The id only. The body would re-leak a title the recipient is not allowed to see.
    for (const uid of [couple.user_a_uid, couple.user_b_uid]) sendTo(uid, { t: 'block:del', id });
    await refreshOverlap(coupleId, req.uid, req.log);
    return { ok: true };
  });

  /**
   * Whole-set replacement of the caller's google blocks (§5): delete then insert, in one
   * transaction, so a mid-insert failure leaves the previous set intact rather than half a calendar.
   */
  app.put('/blocks/google', async (req) => {
    const coupleId = coupleIdFromBody(req.body);
    await assertMember(coupleId, req.uid);
    const body = (req.body ?? {}) as Record<string, unknown>;
    const { intervals } = body;
    if (!Array.isArray(intervals)) throw bad('invalid_intervals');
    // Freebusy only, enforced server-side: the rule does not depend on a client honouring it.
    if ('title' in body) throw bad('title_not_allowed');

    const now = Date.now();
    const parsed = intervals.map((raw) => {
      if (typeof raw !== 'object' || raw === null) throw bad('invalid_interval');
      const iv = raw as Record<string, unknown>;
      if ('title' in iv || 'category' in iv || 'summary' in iv) throw bad('title_not_allowed');
      const start = iv['start_utc'];
      const end = iv['end_utc'];
      if (!Number.isInteger(start) || !Number.isInteger(end)) throw bad('invalid_interval');
      if ((end as number) <= (start as number)) throw bad('invalid_interval');
      return { start: start as number, end: end as number };
    });

    const couple = await withTx(async (c) => {
      const couple = await lockCouple(c, coupleId, req.uid);
      // timezone is NOT NULL and only matters to recurrence expansion, which a freebusy interval
      // never has. Read off the caller's row rather than the body: not the client's to assert.
      const [me] = await c.query<{ timezone: string | null }>(
        'SELECT timezone FROM users WHERE uid = $1',
        [req.uid],
      );
      if (!me?.timezone) throw new HttpError(409, 'timezone_required');

      // Scoped to this user AND source='google': the partner's calendar and everybody's manual
      // blocks are untouched.
      await c.query(
        `DELETE FROM timeblocks WHERE couple_id = $1 AND user_id = $2 AND source = 'google'`,
        [coupleId, req.uid],
      );
      // Ceiling: one round trip per interval. A 14-day freebusy set is dozens of rows; if it ever
      // reaches hundreds, batch it with a single INSERT ... SELECT FROM unnest($1::bigint[], ...).
      for (const iv of parsed) {
        await c.query(
          INSERT_SQL,
          insertParams({
            id: randomUUID(),
            couple_id: coupleId,
            user_id: req.uid,
            title: GOOGLE_TITLE,
            type: 'busy',
            category: null,
            start_utc: iv.start,
            end_utc: iv.end,
            timezone: me.timezone,
            recurrence_rule: null,
            source: 'google',
            visibility: 'bothPartners',
            created_at: now,
          }),
        );
      }
      return couple;
    });

    // ONE message for the whole set. One block:set per interval would cost the client one ranged
    // refetch per busy interval, and an empty replacement cannot be expressed as a block:set at all.
    for (const uid of [couple.user_a_uid, couple.user_b_uid]) {
      sendTo(uid, { t: 'blocks:changed', couple_id: coupleId });
    }
    // One recompute for the whole batch, not one per interval.
    await refreshOverlap(coupleId, req.uid, req.log);
    return { count: parsed.length };
  });
}
