import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { runMigrations } from '../migrate.js';

// The one suite that talks to a real Postgres: a mocked-db test cannot catch a typo'd column name.
// Skips (does not fail) when TEST_DATABASE_URL is unset so the suite stays runnable offline.
// It must run with only a database URL, so it never imports db.ts (which imports config.ts and its
// Firebase requirements) — the int8-parser assertion lives in db.test.ts instead.
const url = process.env['TEST_DATABASE_URL'];

describe.skipIf(!url)('migrations', () => {
  let client: pg.Client;
  let n = 0;

  beforeAll(async () => {
    client = new pg.Client({ connectionString: url });
    await client.connect();
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public');
    await runMigrations(url!);
  });

  afterAll(async () => {
    await client.end();
  });

  /** A couple with both member users, all ids unique per call. */
  async function seedCouple() {
    const s = `t${++n}`;
    const [coupleId, uidA, uidB] = [`c-${s}`, `a-${s}`, `b-${s}`];
    const now = Date.now();
    await client.query(
      'INSERT INTO couples (id, user_a_uid, user_b_uid, paired_at, created_at) VALUES ($1,$2,$3,$4,$4)',
      [coupleId, uidA, uidB, now],
    );
    await client.query(
      `INSERT INTO users (uid, email, timezone, couple_id, created_at)
       VALUES ($1,$1,'Africa/Johannesburg',$3,$4), ($2,$2,'America/New_York',$3,$4)`,
      [uidA, uidB, coupleId, now],
    );
    return { coupleId, uidA, uidB, now };
  }

  function insertBlock(
    coupleId: string,
    uid: string,
    over: Partial<Record<string, unknown>> = {},
  ): Promise<unknown> {
    const now = Date.now();
    const row = {
      id: `blk-${++n}`,
      type: 'busy',
      start_utc: now,
      end_utc: now + 3_600_000,
      source: 'manual',
      visibility: 'bothPartners',
      ...over,
    };
    return client.query(
      `INSERT INTO timeblocks (id, couple_id, user_id, title, type, start_utc, end_utc, timezone,
                               source, visibility, created_at)
       VALUES ($1,$2,$3,'Standup',$4,$5,$6,'Africa/Johannesburg',$7,$8,$9)`,
      [
        row.id,
        coupleId,
        uid,
        row.type,
        row.start_utc,
        row.end_utc,
        row.source,
        row.visibility,
        now,
      ],
    );
  }

  it('applies cleanly to an empty database', async () => {
    for (const table of ['users', 'couples', 'invites', 'timeblocks', 'overlaps_latest']) {
      const { rows } = await client.query<{ r: string | null }>('SELECT to_regclass($1) AS r', [
        `public.${table}`,
      ]);
      expect(rows[0]?.r).toBe(table);
    }
    for (const index of [
      'timeblocks_couple_user_idx',
      'timeblocks_couple_source_idx',
      'invites_status_expires_idx',
      'users_couple_idx',
    ]) {
      const { rows } = await client.query('SELECT 1 FROM pg_indexes WHERE indexname = $1', [index]);
      expect(rows).toHaveLength(1);
    }
  });

  it('is idempotent — applying twice is a no-op', async () => {
    await expect(runMigrations(url!)).resolves.toBeUndefined();
    await expect(runMigrations(url!)).resolves.toBeUndefined();
  });

  it('rejects a timeblock whose end is not after its start', async () => {
    const { coupleId, uidA } = await seedCouple();
    const now = Date.now();
    await expect(
      insertBlock(coupleId, uidA, { start_utc: now, end_utc: now }),
    ).rejects.toThrow(/timeblocks_end_after_start/);
    await expect(
      insertBlock(coupleId, uidA, { start_utc: now, end_utc: now - 1 }),
    ).rejects.toThrow(/timeblocks_end_after_start/);
  });

  it('rejects an invalid block type / source / visibility / couple status', async () => {
    const { coupleId, uidA } = await seedCouple();
    await expect(insertBlock(coupleId, uidA, { type: 'maybe' })).rejects.toThrow(/type/);
    await expect(insertBlock(coupleId, uidA, { source: 'outlook' })).rejects.toThrow(/source/);
    await expect(insertBlock(coupleId, uidA, { visibility: 'public' })).rejects.toThrow(
      /visibility/,
    );
    await expect(
      client.query(
        'INSERT INTO couples (id, user_a_uid, user_b_uid, status, paired_at, created_at) VALUES ($1,$2,$3,$4,$5,$5)',
        [`c-bad-${++n}`, 'x', 'y', 'paused', Date.now()],
      ),
    ).rejects.toThrow(/status/);
  });

  it('cascades timeblocks and overlaps_latest when a couple row is deleted', async () => {
    const { coupleId, uidA, now } = await seedCouple();
    await insertBlock(coupleId, uidA);
    await client.query(
      'INSERT INTO overlaps_latest (couple_id, windows, computed_at, input_hash) VALUES ($1,$2,$3,$4)',
      [coupleId, JSON.stringify([]), now, 'hash'],
    );
    await client.query('DELETE FROM couples WHERE id = $1', [coupleId]);
    const blocks = await client.query('SELECT 1 FROM timeblocks WHERE couple_id = $1', [coupleId]);
    const overlaps = await client.query('SELECT 1 FROM overlaps_latest WHERE couple_id = $1', [
      coupleId,
    ]);
    expect(blocks.rows).toHaveLength(0);
    expect(overlaps.rows).toHaveLength(0);
  });

  it('nulls users.couple_id when the couple is deleted', async () => {
    const { coupleId, uidA } = await seedCouple();
    await client.query('DELETE FROM couples WHERE id = $1', [coupleId]);
    const { rows } = await client.query<{ couple_id: string | null }>(
      'SELECT couple_id FROM users WHERE uid = $1',
      [uidA],
    );
    expect(rows).toHaveLength(1);
    expect(rows[0]?.couple_id).toBeNull();
  });

  it('allows a user row with a null timezone', async () => {
    const uid = `tz-null-${++n}`;
    await client.query('INSERT INTO users (uid, email, created_at) VALUES ($1,$1,$2)', [
      uid,
      Date.now(),
    ]);
    const { rows } = await client.query<{ timezone: string | null }>(
      'SELECT timezone FROM users WHERE uid = $1',
      [uid],
    );
    // Onboarding depends on this: the router guard is `!user.timezone -> /timezone-setup`.
    expect(rows[0]?.timezone).toBeNull();
  });
});
