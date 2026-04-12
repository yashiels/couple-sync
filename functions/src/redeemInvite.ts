import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { CoupleDoc, InviteDoc } from './lib/types';

// ─── Testable business logic ──────────────────────────────────────────────────

export interface RedeemInviteDeps {
  getInvite(code: string): Promise<InviteDoc | null>;
  createCouple(couple: Omit<CoupleDoc, 'createdAt'>): Promise<string>;
  acceptInvite(code: string, coupleId: string): Promise<void>;
  linkUserToCouple(uid: string, coupleId: string): Promise<void>;
}

export async function handleRedeemInvite(
  redeemerUid: string,
  code: string,
  deps: RedeemInviteDeps
): Promise<{ coupleId: string }> {
  const invite = await deps.getInvite(code);

  if (!invite) {
    throw new Error('NOT_FOUND: Invite code not found');
  }
  if (invite.status !== 'pending') {
    throw new Error('FAILED_PRECONDITION: Invite has already been used');
  }
  if (Date.now() > invite.expiresAt) {
    throw new Error('DEADLINE_EXCEEDED: Invite has expired');
  }
  if (invite.createdByUid === redeemerUid) {
    throw new Error('INVALID_ARGUMENT: Cannot redeem your own invite code');
  }

  const coupleId = await deps.createCouple({
    userAUid: invite.createdByUid,
    userBUid: redeemerUid,
    status: 'active',
    pairedAt: Date.now(),
  });

  await Promise.all([
    deps.acceptInvite(code, coupleId),
    deps.linkUserToCouple(invite.createdByUid, coupleId),
    deps.linkUserToCouple(redeemerUid, coupleId),
  ]);

  return { coupleId };
}

// ─── Pending blocks migration ────────────────────────────────────────────────

interface PendingBlockDoc {
  id: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  data: Record<string, any>;
}

/**
 * Read all pending blocks for a user. Must be called during the read phase
 * of a transaction (before any writes).
 */
export async function readPendingBlocks(
  uid: string,
  txn: admin.firestore.Transaction,
  db: admin.firestore.Firestore
): Promise<PendingBlockDoc[]> {
  const pendingRef = db.collection(`users/${uid}/pendingBlocks`);
  const snap = await txn.get(pendingRef);
  return snap.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
}

/**
 * Write migrated blocks to the couple's timeblocks collection and delete
 * the originals from pendingBlocks. Must be called during the write phase
 * of a transaction (after all reads).
 */
export function writeMigratedBlocks(
  uid: string,
  coupleId: string,
  pendingBlocks: PendingBlockDoc[],
  txn: admin.firestore.Transaction,
  db: admin.firestore.Firestore
): void {
  const blocksRef = db.collection(`timeblocks/${coupleId}/blocks`);
  const pendingRef = db.collection(`users/${uid}/pendingBlocks`);

  for (const block of pendingBlocks) {
    const newDocRef = blocksRef.doc();
    txn.set(newDocRef, { ...block.data, userId: uid });
    txn.delete(pendingRef.doc(block.id));
  }
}

// ─── Firestore-backed deps adapter ──────────────────────────────────────────

function firebaseDeps(
  db: admin.firestore.Firestore,
  txn: admin.firestore.Transaction,
  prefetchedInvite: InviteDoc | null
): RedeemInviteDeps {
  const couplesRef = db.collection('couples');
  const invitesRef = db.collection('invites');
  const usersRef = db.collection('users');

  return {
    getInvite: async (_code: string) => prefetchedInvite,

    createCouple: async (data) => {
      const docRef = couplesRef.doc();
      const now = Date.now();
      txn.set(docRef, { ...data, createdAt: now });
      return docRef.id;
    },

    acceptInvite: async (code, coupleId) => {
      txn.update(invitesRef.doc(code), { status: 'accepted', coupleId });
    },

    linkUserToCouple: async (uid, coupleId) => {
      txn.update(usersRef.doc(uid), { coupleId });
    },
  };
}

// ─── Cloud Function export ────────────────────────────────────────────────────

export const redeemInvite = onCall({ region: 'us-central1', timeoutSeconds: 120 }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be signed in to redeem an invite');
  }

  const { code } = request.data as { code: string };
  if (!code || typeof code !== 'string') {
    throw new HttpsError('invalid-argument', 'Invite code is required');
  }

  const db = admin.firestore();
  const uid = request.auth.uid;

  return db.runTransaction(async (txn) => {
    // ── Phase 1: ALL reads ──────────────────────────────────────────────
    // 1. Read invite doc
    const inviteSnap = await txn.get(db.collection('invites').doc(code));
    const invite: InviteDoc | null = inviteSnap.exists
      ? (inviteSnap.data() as InviteDoc)
      : null;

    // 2. Read redeemer's user doc (needed for transaction consistency)
    await txn.get(db.collection('users').doc(uid));

    // 3. Read creator's user doc (if invite exists)
    const creatorUid = invite?.createdByUid;
    if (creatorUid) {
      await txn.get(db.collection('users').doc(creatorUid));
    }

    // 4. Read pendingBlocks for both users
    const redeemerPending = await readPendingBlocks(uid, txn, db);
    const creatorPending = creatorUid
      ? await readPendingBlocks(creatorUid, txn, db)
      : [];

    // ── Phase 2: ALL writes (via handleRedeemInvite + migration) ────────
    // 5. Call handleRedeemInvite with Firestore-backed deps
    let result: { coupleId: string };
    try {
      result = await handleRedeemInvite(
        uid,
        code,
        firebaseDeps(db, txn, invite)
      );
    } catch (err) {
      // Map handleRedeemInvite errors to HttpsError
      const message = err instanceof Error ? err.message : String(err);
      if (message.startsWith('NOT_FOUND:')) {
        throw new HttpsError('not-found', message.replace('NOT_FOUND: ', ''));
      }
      if (message.startsWith('FAILED_PRECONDITION:')) {
        throw new HttpsError('failed-precondition', message.replace('FAILED_PRECONDITION: ', ''));
      }
      if (message.startsWith('DEADLINE_EXCEEDED:')) {
        throw new HttpsError('deadline-exceeded', message.replace('DEADLINE_EXCEEDED: ', ''));
      }
      if (message.startsWith('INVALID_ARGUMENT:')) {
        throw new HttpsError('invalid-argument', message.replace('INVALID_ARGUMENT: ', ''));
      }
      throw err;
    }

    // 6. Migrate pending blocks for both users
    writeMigratedBlocks(uid, result.coupleId, redeemerPending, txn, db);
    if (creatorUid) {
      writeMigratedBlocks(creatorUid, result.coupleId, creatorPending, txn, db);
    }

    return result;
  });
});
