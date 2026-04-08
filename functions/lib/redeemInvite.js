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
// ─── Cloud Function export ────────────────────────────────────────────────────
exports.redeemInvite = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in to redeem an invite');
    }
    const { code } = request.data;
    if (!code || typeof code !== 'string') {
        throw new https_1.HttpsError('invalid-argument', 'Invite code is required');
    }
    const db = admin.firestore();
    const uid = request.auth.uid;
    // Use a Firestore transaction for atomic invite redemption
    return db.runTransaction(async (txn) => {
        const inviteRef = db.collection('invites').doc(code);
        const inviteSnap = await txn.get(inviteRef);
        if (!inviteSnap.exists) {
            throw new https_1.HttpsError('not-found', 'Invite code not found');
        }
        const invite = inviteSnap.data();
        if (invite.status !== 'pending') {
            throw new https_1.HttpsError('failed-precondition', 'Invite has already been used');
        }
        if (Date.now() > invite.expiresAt) {
            throw new https_1.HttpsError('deadline-exceeded', 'Invite has expired');
        }
        if (invite.createdByUid === uid) {
            throw new https_1.HttpsError('invalid-argument', 'Cannot redeem your own invite code');
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
//# sourceMappingURL=redeemInvite.js.map