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
exports.unpairCouple = void 0;
exports.handleUnpairCouple = handleUnpairCouple;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
/**
 * Pure, testable unpair logic. Validates the caller is a current member of an
 * active couple, then delegates all mutations to `deps`. The Firestore-backed
 * adapter below wraps these in a single transaction so the unlink is atomic.
 */
async function handleUnpairCouple(callerUid, deps) {
    const profile = await deps.getCallerProfile(callerUid);
    if (!profile || !profile.coupleId) {
        throw new Error('FAILED_PRECONDITION: You are not currently paired');
    }
    const coupleId = profile.coupleId;
    const couple = await deps.getCouple(coupleId);
    if (!couple) {
        // User doc references a couple that no longer exists. Treat as unpaired —
        // the caller's coupleId is stale and should be cleared.
        throw new Error('NOT_FOUND: Couple no longer exists');
    }
    // Verify the caller is actually a member (defence against a forged coupleId
    // in the user doc pointing at someone else's couple).
    const partnerUid = couple.userAUid === callerUid
        ? couple.userBUid
        : couple.userBUid === callerUid
            ? couple.userAUid
            : null;
    if (partnerUid === null) {
        throw new Error('PERMISSION_DENIED: You are not a member of this couple');
    }
    if (couple.status === 'inactive') {
        // Idempotent guard: already unpaired. Still clear the caller's stale
        // coupleId so they can re-pair.
        await deps.unlinkUser(callerUid);
        return { coupleId, partnerUid };
    }
    const entry = {
        at: Date.now(),
        reason: 'manual_unpair',
    };
    await deps.deactivateCouple(coupleId, entry);
    await Promise.all([
        deps.unlinkUser(callerUid),
        deps.unlinkUser(partnerUid),
    ]);
    await deps.deleteSharedData(coupleId);
    return { coupleId, partnerUid };
}
// ─── Firestore-backed deps adapter ───────────────────────────────────────────
function firebaseDeps(db, txn) {
    const couplesRef = db.collection('couples');
    const usersRef = db.collection('users');
    return {
        getCallerProfile: async (uid) => {
            const snap = await txn.get(usersRef.doc(uid));
            if (!snap.exists)
                return null;
            const data = snap.data();
            return { coupleId: data.coupleId };
        },
        getCouple: async (coupleId) => {
            const snap = await txn.get(couplesRef.doc(coupleId));
            if (!snap.exists)
                return null;
            return snap.data();
        },
        deactivateCouple: async (coupleId, entry) => {
            // ponytail: FieldValue.arrayUnion keeps any prior history intact.
            txn.update(couplesRef.doc(coupleId), {
                status: 'inactive',
                unpairHistory: admin.firestore.FieldValue.arrayUnion([entry]),
            });
        },
        unlinkUser: async (uid) => {
            txn.update(usersRef.doc(uid), {
                coupleId: admin.firestore.FieldValue.delete(),
            });
        },
        // ponytail: recursiveDelete is fire-and-forget best-effort cleanup. It
        // runs AFTER the transaction commits (see onCall below) so a failure here
        // never leaves users in a half-unlinked state. Orphaned timeblocks under
        // a now-inactive coupleId are harmless (a fresh pairing mints a new id),
        // so partial failure is acceptable.
        deleteSharedData: async (coupleId) => {
            await Promise.all([
                db.recursiveDelete(db.collection(`timeblocks/${coupleId}/blocks`)),
                db.recursiveDelete(db.doc(`overlaps/${coupleId}/windows/latest`)),
            ]);
        },
    };
}
// ─── Cloud Function export ───────────────────────────────────────────────────
exports.unpairCouple = (0, https_1.onCall)({ region: 'us-central1', timeoutSeconds: 120, enforceAppCheck: true }, async (request) => {
    if (!request.app) {
        throw new https_1.HttpsError('failed-precondition', 'App Check token missing');
    }
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in to unpair');
    }
    const callerUid = request.auth.uid;
    const db = admin.firestore();
    // Phase 1: atomic unlink + couple deactivation in a transaction.
    const result = await db.runTransaction(async (txn) => {
        const deps = firebaseDeps(db, txn);
        try {
            return await handleUnpairCouple(callerUid, deps);
        }
        catch (err) {
            const message = err instanceof Error ? err.message : String(err);
            if (message.startsWith('FAILED_PRECONDITION:')) {
                throw new https_1.HttpsError('failed-precondition', message.replace('FAILED_PRECONDITION: ', ''));
            }
            if (message.startsWith('NOT_FOUND:')) {
                throw new https_1.HttpsError('not-found', message.replace('NOT_FOUND: ', ''));
            }
            if (message.startsWith('PERMISSION_DENIED:')) {
                throw new https_1.HttpsError('permission-denied', message.replace('PERMISSION_DENIED: ', ''));
            }
            throw err;
        }
    });
    // Phase 2: best-effort shared-data cleanup after the transaction commits.
    // A rejection here is swallowed — the unpair itself already succeeded.
    try {
        await db.recursiveDelete(db.collection(`timeblocks/${result.coupleId}/blocks`));
        await db.recursiveDelete(db.doc(`overlaps/${result.coupleId}/windows/latest`));
    }
    catch (_a) {
        // Intentional: see comment on firebaseDeps.deleteSharedData above.
    }
    return result;
});
//# sourceMappingURL=unpairCouple.js.map