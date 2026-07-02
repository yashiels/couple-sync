"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.redeemInvite = void 0;
exports.handleRedeemInvite = handleRedeemInvite;
exports.readPendingBlocks = readPendingBlocks;
exports.writeMigratedBlocks = writeMigratedBlocks;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
async function handleRedeemInvite(redeemerUid, code, deps) {
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
/**
 * Read all pending blocks for a user. Must be called during the read phase
 * of a transaction (before any writes).
 */
async function readPendingBlocks(uid, txn, db) {
    const pendingRef = db.collection(`users/${uid}/pendingBlocks`);
    const snap = await txn.get(pendingRef);
    return snap.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
}
/**
 * Write migrated blocks to the couple's timeblocks collection and delete
 * the originals from pendingBlocks. Must be called during the write phase
 * of a transaction (after all reads).
 */
function writeMigratedBlocks(uid, coupleId, pendingBlocks, txn, db) {
    const blocksRef = db.collection(`timeblocks/${coupleId}/blocks`);
    const pendingRef = db.collection(`users/${uid}/pendingBlocks`);
    for (const block of pendingBlocks) {
        const newDocRef = blocksRef.doc();
        txn.set(newDocRef, Object.assign(Object.assign({}, block.data), { userId: uid }));
        txn.delete(pendingRef.doc(block.id));
    }
}
// ─── Firestore-backed deps adapter ──────────────────────────────────────────
function firebaseDeps(db, txn, prefetchedInvite) {
    const couplesRef = db.collection('couples');
    const invitesRef = db.collection('invites');
    const usersRef = db.collection('users');
    return {
        getInvite: async (_code) => prefetchedInvite,
        createCouple: async (data) => {
            const docRef = couplesRef.doc();
            const now = Date.now();
            txn.set(docRef, Object.assign(Object.assign({}, data), { createdAt: now }));
            return docRef.id;
        },
        acceptInvite: async (code, coupleId) => {
            // status was already set to 'redeemed' in the compare-and-swap step;
            // here we stamp the resulting coupleId onto the invite doc.
            txn.update(invitesRef.doc(code), { coupleId });
        },
        linkUserToCouple: async (uid, coupleId) => {
            txn.update(usersRef.doc(uid), { coupleId });
        },
    };
}
// ─── Cloud Function export ────────────────────────────────────────────────────
exports.redeemInvite = (0, https_1.onCall)({ region: 'us-central1', timeoutSeconds: 120, enforceAppCheck: true }, async (request) => {
    if (!request.app) {
        throw new https_1.HttpsError('failed-precondition', 'App Check token missing');
    }
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in to redeem an invite');
    }
    const { code } = request.data;
    if (!code || typeof code !== 'string') {
        throw new https_1.HttpsError('invalid-argument', 'Invite code is required');
    }
    const db = admin.firestore();
    const uid = request.auth.uid;
    return db.runTransaction(async (txn) => {
        // ── Phase 1: ALL reads ──────────────────────────────────────────────
        // 1. Read invite doc
        const inviteSnap = await txn.get(db.collection('invites').doc(code));
        const invite = inviteSnap.exists
            ? inviteSnap.data()
            : null;
        // 2. Read creator's user doc (if invite exists)
        const creatorUid = invite === null || invite === void 0 ? void 0 : invite.createdByUid;
        if (creatorUid) {
            await txn.get(db.collection('users').doc(creatorUid));
        }
        // 3. Read pendingBlocks for both users
        const redeemerPending = await readPendingBlocks(uid, txn, db);
        const creatorPending = creatorUid
            ? await readPendingBlocks(creatorUid, txn, db)
            : [];
        // ── Phase 2: ALL writes (via handleRedeemInvite + migration) ────────
        // 5a. Compare-and-swap: atomically claim the invite by marking it
        //     'redeemed' as the very first write in the transaction. Two
        //     concurrent transactions will both read status === 'pending' in
        //     Phase 1, but only one can commit the conflicting update on the
        //     same invite doc — Firestore will abort and retry the loser.
        //     handleRedeemInvite (below) still validates the status and all
        //     other preconditions before any further writes occur.
        if (invite) {
            txn.update(db.collection('invites').doc(code), { status: 'redeemed' });
        }
        // 5b. Call handleRedeemInvite with Firestore-backed deps
        let result;
        try {
            result = await handleRedeemInvite(uid, code, firebaseDeps(db, txn, invite));
        }
        catch (err) {
            // Map handleRedeemInvite errors to HttpsError
            const message = err instanceof Error ? err.message : String(err);
            if (message.startsWith('NOT_FOUND:')) {
                throw new https_1.HttpsError('not-found', message.replace('NOT_FOUND: ', ''));
            }
            if (message.startsWith('FAILED_PRECONDITION:')) {
                throw new https_1.HttpsError('failed-precondition', message.replace('FAILED_PRECONDITION: ', ''));
            }
            if (message.startsWith('DEADLINE_EXCEEDED:')) {
                throw new https_1.HttpsError('deadline-exceeded', message.replace('DEADLINE_EXCEEDED: ', ''));
            }
            if (message.startsWith('INVALID_ARGUMENT:')) {
                throw new https_1.HttpsError('invalid-argument', message.replace('INVALID_ARGUMENT: ', ''));
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
//# sourceMappingURL=redeemInvite.js.map