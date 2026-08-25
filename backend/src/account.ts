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
    // Lock the user row first. /invites/:code/redeem locks both users FOR UPDATE and re-reads their
    // couple_id after acquiring, so this serializes deletion against pairing: redeem either commits
    // first — and the couple SELECT below then finds and tears down the couple it created — or it runs
    // after the user row is gone and fails cleanly with unknown_user, never stranding a half-paired
    // couple with a deleted member. No rows (an idempotent re-run on an already-deleted uid) is fine.
    await c.query('SELECT couple_id FROM users WHERE uid = $1 FOR UPDATE', [uid]);
    await c.query(
      `INSERT INTO deleted_accounts (uid, deleted_at) VALUES ($1, $2) ON CONFLICT (uid) DO NOTHING`,
      [uid, Date.now()],
    );

    // At most one active couple. Tear it down under the same advisory lock refreshOverlap takes, held
    // before the overlaps_latest delete, so an in-flight compute cannot resurrect the row afterwards.
    const [couple] = await c.query<CoupleRow>(
      `SELECT * FROM couples WHERE (user_a_uid = $1 OR user_b_uid = $1) AND status = 'active'`,
      [uid],
    );
    let partnerUid: string | null = null;
    if (couple) {
      await c.query('SELECT pg_advisory_xact_lock(hashtext($1))', [couple.id]);
      await c.query(`UPDATE couples SET status = 'inactive' WHERE id = $1`, [couple.id]);
      await c.query('UPDATE users SET couple_id = NULL WHERE uid IN ($1, $2)', [
        couple.user_a_uid,
        couple.user_b_uid,
      ]);
      await c.query('DELETE FROM timeblocks WHERE couple_id = $1', [couple.id]);
      await c.query('DELETE FROM overlaps_latest WHERE couple_id = $1', [couple.id]);
      partnerUid = couple.user_a_uid === uid ? couple.user_b_uid : couple.user_a_uid;
    }

    // The user's own row. invites (created_by_uid) and any timeblocks (user_id) cascade on this delete.
    await c.query('DELETE FROM users WHERE uid = $1', [uid]);

    return couple ? { partnerUid: partnerUid as string, coupleId: couple.id } : null;
  });

  await deleteAuthUser(uid);
  await query('UPDATE deleted_accounts SET completed_at = $2 WHERE uid = $1', [uid, Date.now()]);

  // After the commit, tell the partner so their app resets to /pairing — same message unpair sends.
  if (notify) sendTo(notify.partnerUid, { t: 'unpair', couple_id: notify.coupleId });
}

/** True if this uid has been deleted — the non-resurrection check `/auth/verify` calls. */
export async function isDeleted(uid: string): Promise<boolean> {
  const rows = await query('SELECT 1 FROM deleted_accounts WHERE uid = $1', [uid]);
  return rows.length > 0;
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
  for (const { uid } of pending) {
    await deleteAuthUser(uid);
    await query('UPDATE deleted_accounts SET completed_at = $2 WHERE uid = $1', [uid, Date.now()]);
  }
  return pending.length;
}
