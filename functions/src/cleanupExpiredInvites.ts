import * as admin from 'firebase-admin';
import { onSchedule } from 'firebase-functions/v2/scheduler';

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const BATCH_SIZE = 500;

// ─── Testable business logic ──────────────────────────────────────────────────

interface CleanupDeps {
  getExpiredInvites(cutoffMs: number): Promise<string[]>;
  deleteInvite(id: string): Promise<void>;
}

export async function handleCleanupExpiredInvites(deps: CleanupDeps): Promise<void> {
  const cutoff = Date.now() - SEVEN_DAYS_MS;
  const expiredIds = await deps.getExpiredInvites(cutoff);

  // Process in batches to avoid overloading Firestore
  for (let i = 0; i < expiredIds.length; i += BATCH_SIZE) {
    const batch = expiredIds.slice(i, i + BATCH_SIZE);
    await Promise.all(batch.map((id) => deps.deleteInvite(id)));
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
      deleteInvite: async (id) => {
        await db.collection('invites').doc(id).delete();
      },
    });
  }
);
