import * as admin from 'firebase-admin';
import { onSchedule } from 'firebase-functions/v2/scheduler';

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const BATCH_SIZE = 500;

// ─── Testable business logic ──────────────────────────────────────────────────

interface CleanupDeps {
  getExpiredInvites(cutoffMs: number): Promise<string[]>;
  /** Delete a batch of up to 500 invite IDs in a single atomic operation. */
  deleteInviteBatch(ids: string[]): Promise<void>;
}

export async function handleCleanupExpiredInvites(deps: CleanupDeps): Promise<void> {
  const cutoff = Date.now() - SEVEN_DAYS_MS;
  const expiredIds = await deps.getExpiredInvites(cutoff);

  // Commit one WriteBatch per 500-doc chunk (Firestore batch limit).
  for (let i = 0; i < expiredIds.length; i += BATCH_SIZE) {
    await deps.deleteInviteBatch(expiredIds.slice(i, i + BATCH_SIZE));
  }
}

// ─── Cloud Function export ────────────────────────────────────────────────────

export const cleanupExpiredInvites = onSchedule(
  { schedule: '0 3 * * *', region: 'us-central1', timeZone: 'UTC' },
  async () => {
    const db = admin.firestore();

    await handleCleanupExpiredInvites({
      getExpiredInvites: async (cutoffMs) => {
        const snap = await db
          .collection('invites')
          .where('expiresAt', '<', cutoffMs)
          .select()
          .get();
        return snap.docs.map((d) => d.id);
      },
      deleteInviteBatch: async (ids) => {
        const batch = db.batch();
        ids.forEach((id) => batch.delete(db.collection('invites').doc(id)));
        await batch.commit();
      },
    });
  }
);
