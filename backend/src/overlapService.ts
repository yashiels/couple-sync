import type { FastifyBaseLogger } from 'fastify';
import { withTx } from './db.js';
import {
  computeInputHash,
  computeOverlap,
  type OverlapInput,
  type OverlapWindow,
} from './overlap/index.js';
import { pushOverlapChanged } from './push.js';
import { sendTo } from './sockets.js';
import {
  toEngineBlock,
  type BlockRow,
  type CoupleRow,
  type UserRow,
  type WsMessage,
} from './wire.js';

export interface RefreshResult {
  windows: OverlapWindow[];
  computedAt: number;
  changed: boolean; // false when input_hash matched the stored row
}

/** Private. What the transaction returns internally: the public result plus what fanOut needs. */
interface Committed extends RefreshResult {
  coupleId: string;
  recipients: { uid: string; timezone: string; tokens: string[]; notificationsEnabled: boolean }[];
}

interface StoredRow {
  windows: OverlapWindow[];
  computed_at: number;
  input_hash: string;
}

/** One row, four columns, one round trip. `null` for anything that does not exist. */
interface LoadedRow {
  couple: CoupleRow | null;
  users: UserRow[] | null;
  blocks: BlockRow[] | null;
  stored: StoredRow | null;
}

// Both user rows come off the couple row rather than `users WHERE couple_id = $1`, so a stale
// users.couple_id can never silently reduce the input to one partner.
const LOAD_SQL = `
  WITH cp AS (SELECT * FROM couples WHERE id = $1)
  SELECT (SELECT to_jsonb(cp) FROM cp)                                          AS couple,
         (SELECT jsonb_agg(u) FROM users u, cp
                 WHERE u.uid IN (cp.user_a_uid, cp.user_b_uid))                 AS users,
         (SELECT jsonb_agg(b) FROM timeblocks b WHERE b.couple_id = $1)         AS blocks,
         (SELECT to_jsonb(o) FROM overlaps_latest o WHERE o.couple_id = $1)     AS stored`;

const UPSERT_SQL = `
  INSERT INTO overlaps_latest (couple_id, windows, computed_at, input_hash)
  VALUES ($1, $2::jsonb, $3, $4)
  ON CONFLICT (couple_id) DO UPDATE
     SET windows = EXCLUDED.windows,
         computed_at = EXCLUDED.computed_at,
         input_hash = EXCLUDED.input_hash`;

/**
 * Load both partners' blocks and prefs, compute, and upsert only when the hash changed.
 * @param triggeredBy uid whose action caused this; that user is never pushed.
 *                    null for a read-path refresh.
 * @param log this module has no logger of its own, and a failed post-commit push must be
 *            logged somewhere real.
 * Callers: every block write, a tz/late-night PATCH, invite redeem, and GET /overlaps/latest.
 */
export async function refreshOverlap(
  coupleId: string,
  triggeredBy: string | null,
  log: FastifyBaseLogger,
): Promise<RefreshResult> {
  // NOT `return withTx(...)` — the fan-out must happen AFTER the commit, so the tx result is
  // captured first and the side effects run outside it.
  const committed: Committed = await withTx(async (c) => {
    // Serializes refreshes for THIS couple only; different couples never block each other.
    // Without it, two concurrent writes can interleave load -> compute -> upsert and store the
    // older result, and every concurrent first-read after an hour rollover would write, fan out
    // and push. Released automatically at COMMIT/ROLLBACK.
    // hashtext is a 32-bit int, so two couple ids can collide and wait on each other. Harmless:
    // a spurious wait, never a wrong result.
    await c.query('SELECT pg_advisory_xact_lock(hashtext($1))', [coupleId]);

    const [loaded] = await c.query<LoadedRow>(LOAD_SQL, [coupleId]);
    const couple = loaded?.couple ?? null;
    const users = loaded?.users ?? [];
    const userA = users.find((u) => u.uid === couple?.user_a_uid);
    const userB = users.find((u) => u.uid === couple?.user_b_uid);

    // one captured `now`, one input object, used for BOTH the hash and the compute — calling
    // Date.now() twice can straddle an hour boundary and make the stored hash describe a
    // different computation than the one that ran.
    const now = Date.now();

    // Unpair flips status to 'inactive' under this same lock, so a refresh that lost that race
    // must not write a fresh row for a couple that no longer exists. A missing timezone is the
    // same story from the other end: pairing is gated behind onboarding, so it means this couple
    // is not ready to be computed either.
    if (couple?.status !== 'active' || !userA?.timezone || !userB?.timezone) {
      return { windows: [], computedAt: now, changed: false, coupleId, recipients: [] };
    }

    // `onlyMe` blocks go in unscrubbed: hiding a title is presentation, but the interval must
    // still shape the overlap.
    const blocks = loaded?.blocks ?? [];
    const input: OverlapInput = {
      blocksA: blocks.filter((b) => b.user_id === couple.user_a_uid).map(toEngineBlock),
      blocksB: blocks.filter((b) => b.user_id === couple.user_b_uid).map(toEngineBlock),
      timezoneA: userA.timezone,
      timezoneB: userB.timezone,
      prefsA: { showLateNightWindows: userA.show_late_night_windows },
      prefsB: { showLateNightWindows: userB.show_late_night_windows },
      now,
    };
    const recipients = [userA, userB].map((u) => ({
      uid: u.uid,
      timezone: u.timezone!,
      tokens: u.fcm_tokens,
      notificationsEnabled: u.notifications_enabled,
    }));

    const hash = computeInputHash(input);
    const stored = loaded?.stored ?? null;
    if (stored && hash === stored.input_hash) {
      return {
        windows: stored.windows,
        computedAt: stored.computed_at,
        changed: false,
        coupleId,
        recipients,
      };
    }

    // ponytail: inline on the request thread. ~100ms for 500 recurring blocks/partner against a
    // 500ms budget. A job queue is the upgrade path only if p99 write latency starts to matter.
    const windows = computeOverlap(input);

    // No WS, no FCM, no network call inside the tx: a notification can otherwise reach a device
    // before the data is committed and readable, and awaiting FCM while holding a pool connection
    // starves the pool exactly when concurrent refreshes need one.
    await c.query(UPSERT_SQL, [coupleId, JSON.stringify(windows), now, hash]);
    return { windows, computedAt: now, changed: true, coupleId, recipients };
  });

  if (committed.changed) await fanOut(committed, triggeredBy, log);
  // Preserve the real value — hardcoding `changed: true` here would erase the dedup result.
  return { windows: committed.windows, computedAt: committed.computedAt, changed: committed.changed };
}

async function fanOut(c: Committed, triggeredBy: string | null, log: FastifyBaseLogger) {
  const msg: WsMessage = {
    t: 'overlap',
    couple_id: c.coupleId,
    windows: c.windows,
    computed_at: c.computedAt,
  };

  // 1. BOTH WS sends first, synchronously, before ANY await — an await between them would let a
  //    newer refresh's message overtake an older one and leave a store on stale windows. The
  //    writer gets one too: their own window list changed, so the device that made the edit is
  //    otherwise the one showing stale data. sendTo's boolean replaces an isOnline check, which
  //    would be two round trips with a disconnect window in between.
  const delivered = new Map(c.recipients.map((r) => [r.uid, sendTo(r.uid, msg)]));

  // 2. Then the pushes — suppressed for triggeredBy, because nobody should be notified about
  //    their own action. allSettled + log, because the mutation is already committed: a dead FCM
  //    endpoint must not turn a successful write into an HTTP 500.
  const results = await Promise.allSettled(
    c.recipients
      .filter((r) => r.uid !== triggeredBy && !delivered.get(r.uid) && r.notificationsEnabled)
      .map((r) => pushOverlapChanged(r.uid, r.tokens, c.windows, r.timezone)),
  );
  for (const r of results) if (r.status === 'rejected') log.warn({ err: r.reason }, 'push failed');
}
