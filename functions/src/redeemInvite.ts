import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { CoupleDoc, InviteDoc } from './lib/types';

// ─── Testable business logic ──────────────────────────────────────────────────

interface RedeemInviteDeps {
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

// ─── Cloud Function export ────────────────────────────────────────────────────

export const redeemInvite = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be signed in to redeem an invite');
  }

  const { code } = request.data as { code: string };
  if (!code || typeof code !== 'string') {
    throw new HttpsError('invalid-argument', 'Invite code is required');
  }

  const db = admin.firestore();
  const uid = request.auth.uid;

  // Use a Firestore transaction for atomic invite redemption
  return db.runTransaction(async (txn) => {
    const inviteRef = db.collection('invites').doc(code);
    const inviteSnap = await txn.get(inviteRef);

    if (!inviteSnap.exists) {
      throw new HttpsError('not-found', 'Invite code not found');
    }

    const invite = inviteSnap.data() as InviteDoc;

    if (invite.status !== 'pending') {
      throw new HttpsError('failed-precondition', 'Invite has already been used');
    }
    if (Date.now() > invite.expiresAt) {
      throw new HttpsError('deadline-exceeded', 'Invite has expired');
    }
    if (invite.createdByUid === uid) {
      throw new HttpsError('invalid-argument', 'Cannot redeem your own invite code');
    }

    const coupleRef = db.collection('couples').doc();
    const coupleId = coupleRef.id;
    const now = Date.now();

    txn.set(coupleRef, {
      userAUid: invite.createdByUid,
      userBUid: uid,
      status: 'active',
      pairedAt: now,
      createdAt: now,
    });

    txn.update(inviteRef, { status: 'accepted', coupleId });
    txn.update(db.collection('users').doc(invite.createdByUid), { coupleId });
    txn.update(db.collection('users').doc(uid), { coupleId });

    return { coupleId };
  });
});
