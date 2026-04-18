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

    // The triggering user's data is already in the event — avoid a redundant read.
    const triggeringUid = event.params.uid as string;
    const triggeringData = after as { timezone?: string; showLateNightWindows?: boolean };
    const otherUid =
      triggeringUid === couple.userAUid ? couple.userBUid : couple.userAUid;
    const otherSnap = await db.collection('users').doc(otherUid).get();
    const otherData = otherSnap.data() as
      | { timezone?: string; showLateNightWindows?: boolean }
      | undefined;

    const [userA, userB] =
      triggeringUid === couple.userAUid
        ? [triggeringData, otherData]
        : [otherData, triggeringData];

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
