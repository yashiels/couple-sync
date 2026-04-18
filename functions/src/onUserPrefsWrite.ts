import * as admin from 'firebase-admin';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { computeBlockHash, computeOverlap } from './lib/overlap';
import { CoupleDoc, TimeBlock } from './lib/types';

/**
 * Recomputes the couple's overlap windows when a user toggles a preference
 * that affects windowing (currently: showLateNightWindows).
 */
export const onUserPrefsWrite = onDocumentUpdated(
  { document: 'users/{uid}', region: 'us-central1', memory: '512MiB', timeoutSeconds: 120 },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const prefChanged =
      (before.showLateNightWindows ?? false) !== (after.showLateNightWindows ?? false);
    if (!prefChanged) return;

    const coupleId = after.coupleId as string | undefined;
    if (!coupleId) return;

    const db = admin.firestore();
    const coupleSnap = await db.collection('couples').doc(coupleId).get();
    if (!coupleSnap.exists) return;
    const couple = coupleSnap.data() as CoupleDoc;

    const blocksSnap = await db
      .collection('timeblocks').doc(coupleId).collection('blocks').get();
    const allBlocks = blocksSnap.docs.map(
      (d) => ({ id: d.id, ...(d.data() as TimeBlock) }),
    );
    const blocksA = allBlocks.filter((b) => b.userId === couple.userAUid);
    const blocksB = allBlocks.filter((b) => b.userId === couple.userBUid);

    const [userASnap, userBSnap] = await Promise.all([
      db.collection('users').doc(couple.userAUid).get(),
      db.collection('users').doc(couple.userBUid).get(),
    ]);
    const userA = userASnap.data() as
      | { timezone?: string; showLateNightWindows?: boolean }
      | undefined;
    const userB = userBSnap.data() as
      | { timezone?: string; showLateNightWindows?: boolean }
      | undefined;

    const windows = computeOverlap(
      blocksA,
      blocksB,
      userA?.timezone ?? 'UTC',
      userB?.timezone ?? 'UTC',
      Date.now(),
      { showLateNightWindows: userA?.showLateNightWindows === true },
      { showLateNightWindows: userB?.showLateNightWindows === true },
    );

    await db
      .collection('overlaps').doc(coupleId).collection('windows').doc('latest').set({
        windows,
        computedAt: Date.now(),
        blockHashA: computeBlockHash(blocksA),
        blockHashB: computeBlockHash(blocksB),
      });
  },
);
