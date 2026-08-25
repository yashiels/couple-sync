import { query, withTx } from './db.js';
import { deleteAuthUser } from './firebase.js';
import { sendTo } from './sockets.js';
import type { CoupleRow } from './wire.js';

/**
 * Delete a user's account and all their data (§B1). The one implementation behind both the
 * self-authenticated `DELETE /account` route and the operator-fulfilled admin path.
 *
 * Deletion spans two stores that cannot share a transaction — Postgres and Firebase Auth — so this is
 * **resumable, idempotent, and non-resurrectable**:
 *
 *  1. In one Postgres transaction: write the `deleted_accounts` tombstone FIRST (it outlives the user
 *     row and is what `/auth/verify` checks to refuse recreating the account), tear down an active
 *     couple exactly as unpair does, then delete the user row (their invites and remaining timeblocks
 *     cascade). The tombstone therefore only exists if every Postgres delete committed.
 *  2. Outside the transaction: delete the Firebase Auth user (idempotent — a missing user is success).
 *  3. Stamp `completed_at`.
 *
 * A crash after (1) but before (3) leaves an incomplete tombstone with the Postgres data already gone;
 * `reconcilePendingDeletions()` (run by cron) finishes step 2–3. Re-running deleteAccount() for the
 * same uid is safe: the tombstone insert is a no-op, the couple is already inactive/gone, the user row
 * is already gone, and the Firebase delete is idempotent.
 */
export async function deleteAccount(uid: string): Promise<void> {
  const notify = await withTx(async (c) => {
    // Per-account advisory lock, FIRST. /auth/verify takes the same lock (hashtext(uid)) around its
    // tombstone-check + upsert, so the two serialize: a verify cannot read "no tombstone", pause, and
    // then recreate the row this deletion is committing (a TOCTOU resurrection).
    await c.query('SELECT pg_advisory_xact_lock(hashtext($1))', [uid]);
    // Lock the user row too. /invites/:code/redeem locks both users FOR UPDATE and re-reads their
    // couple_id after acquiring, so this serializes deletion against pairing: redeem either commits
    // first — and the couple sweep below then removes the couple it created — or it runs after the user
    // row is gone and fails cleanly with unknown_user. No rows (an idempotent re-run) is fine.
    await c.query('SELECT couple_id FROM users WHERE uid = $1 FOR UPDATE', [uid]);
    await c.query(
      `INSERT INTO deleted_accounts (uid, deleted_at) VALUES ($1, $2) ON CONFLICT (uid) DO NOTHING`,
      [uid, Date.now()],
    );

    // Remove EVERY couple that references this uid — active or inactive — so no couple row is left
    // retaining the deleted uid, its partner association, or its timestamps (the privacy policy promises
    // only a uid-tombstone survives). Take refreshOverlap's advisory lock per couple first, so an
    // in-flight compute cannot resurrect overlaps_latest for a couple we are deleting.
    const couples = await c.query<CoupleRow>(
      `SELECT * FROM couples WHERE user_a_uid = $1 OR user_b_uid = $1`,
      [uid],
    );
    let notify: { partnerUid: string; coupleId: string } | null = null;
    for (const couple of couples) {
      await c.query('SELECT pg_advisory_xact_lock(hashtext($1))', [couple.id]);
      if (couple.status === 'active') {
        notify = {
          partnerUid: couple.user_a_uid === uid ? couple.user_b_uid : couple.user_a_uid,
          coupleId: couple.id,
        };
      }
    }
    // ON DELETE CASCADE clears each couple's timeblocks + overlaps_latest; ON DELETE SET NULL clears the
    // partner's users.couple_id and any invites.couple_id (schema in migrations/001_init.sql).
    await c.query('DELETE FROM couples WHERE user_a_uid = $1 OR user_b_uid = $1', [uid]);

    // The user's own row. invites (created_by_uid) and any timeblocks (user_id) cascade on this delete.
    await c.query('DELETE FROM users WHERE uid = $1', [uid]);

    return notify;
  });

  // Postgres has committed, so the account IS deleted — even if anything below fails.
  // Notify the partner NOW, before the fallible Firebase step, so a Firebase outage cannot swallow the
  // WS reset. Best-effort: a socket send can throw, and that must not fail an already-committed
  // deletion — the partner self-heals on its next fetch (its couple_id is now null).
  if (notify) {
    try {
      sendTo(notify.partnerUid, { t: 'unpair', couple_id: notify.coupleId });
    } catch {
      // ignore — deletion already succeeded
    }
  }

  // Best-effort Firebase Auth delete. A failure leaves completed_at NULL and the cron sweep retries; it
  // must NOT throw, or the caller would report deletion "failed" and stay signed in despite the
  // irreversible Postgres delete. The /auth/verify tombstone already blocks the account regardless.
  try {
    await deleteAuthUser(uid);
    await query('UPDATE deleted_accounts SET completed_at = $2 WHERE uid = $1', [uid, Date.now()]);
  } catch {
    // reconcilePendingDeletions() finishes it.
  }
}

/**
 * Finish any deletion that committed in Postgres but did not complete the Firebase Auth delete (a crash
 * between the transaction and `completed_at`). Idempotent and safe to run repeatedly; the cron timer
 * calls it. Returns how many were reconciled.
 */
export async function reconcilePendingDeletions(): Promise<number> {
  const pending = await query<{ uid: string }>(
    'SELECT uid FROM deleted_accounts WHERE completed_at IS NULL',
  );
  let done = 0;
  for (const { uid } of pending) {
    // Per-uid: one Firebase error must not abort the sweep and starve every tombstone behind it. The
    // next tick retries whatever stayed incomplete.
    try {
      await deleteAuthUser(uid);
      await query('UPDATE deleted_accounts SET completed_at = $2 WHERE uid = $1', [uid, Date.now()]);
      done++;
    } catch (err) {
      console.error('[reconcile] account deletion cleanup failed', uid, err);
    }
  }
  return done;
}
