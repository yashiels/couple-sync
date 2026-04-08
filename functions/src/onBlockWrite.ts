import * as admin from 'firebase-admin';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { computeBlockHash, computeOverlap } from './lib/overlap';
import { CoupleDoc, OverlapResult, TimeBlock } from './lib/types';

// ─── Testable business logic ──────────────────────────────────────────────────

interface BlockWriteDeps {
  getCouple(id: string): Promise<CoupleDoc | null>;
  getUser(uid: string): Promise<{ timezone: string } | null>;
  getBlocks(coupleId: string): Promise<TimeBlock[]>;
  getCurrentOverlap(coupleId: string): Promise<{ blockHashA: string; blockHashB: string } | null>;
  saveOverlap(coupleId: string, result: OverlapResult): Promise<void>;
}

export async function handleBlockWrite(
  coupleId: string,
  deps: BlockWriteDeps
): Promise<void> {
  const couple = await deps.getCouple(coupleId);
  if (!couple) return;

  const allBlocks = await deps.getBlocks(coupleId);
  const blocksA = allBlocks.filter((b) => b.userId === couple.userAUid);
  const blocksB = allBlocks.filter((b) => b.userId === couple.userBUid);

  const hashA = computeBlockHash(blocksA);
  const hashB = computeBlockHash(blocksB);

  // Skip recomputation if nothing has changed
  const existing = await deps.getCurrentOverlap(coupleId);
  if (existing && existing.blockHashA === hashA && existing.blockHashB === hashB) return;

  const [userA, userB] = await Promise.all([
    deps.getUser(couple.userAUid),
    deps.getUser(couple.userBUid),
  ]);

  const timezoneA = userA?.timezone ?? 'UTC';
  const timezoneB = userB?.timezone ?? 'UTC';
  const windows = computeOverlap(blocksA, blocksB, timezoneA, timezoneB);

  await deps.saveOverlap(coupleId, {
    windows,
    computedAt: Date.now(),
    blockHashA: hashA,
    blockHashB: hashB,
  });
}

// ─── Cloud Function export ────────────────────────────────────────────────────

export const onBlockWrite = onDocumentWritten(
  'timeblocks/{coupleId}/blocks/{blockId}',
  async (event) => {
    const db = admin.firestore();
    const { coupleId } = event.params;

    await handleBlockWrite(coupleId, {
      getCouple: async (id) => {
        const snap = await db.collection('couples').doc(id).get();
        return snap.exists ? (snap.data() as CoupleDoc) : null;
      },
      getUser: async (uid) => {
        const snap = await db.collection('users').doc(uid).get();
        return snap.exists ? (snap.data() as { timezone: string }) : null;
      },
      getBlocks: async (cId) => {
        const snap = await db.collection('timeblocks').doc(cId).collection('blocks').get();
        return snap.docs.map((d) => ({ id: d.id, ...(d.data() as TimeBlock) }));
      },
      getCurrentOverlap: async (cId) => {
        const snap = await db
          .collection('overlaps').doc(cId).collection('windows').doc('latest').get();
        return snap.exists
          ? (snap.data() as { blockHashA: string; blockHashB: string })
          : null;
      },
      saveOverlap: async (cId, result) => {
        await db
          .collection('overlaps').doc(cId).collection('windows').doc('latest').set(result);
      },
    });
  }
);
