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
exports.cleanupExpiredInvites = void 0;
exports.handleCleanupExpiredInvites = handleCleanupExpiredInvites;
const admin = __importStar(require("firebase-admin"));
const scheduler_1 = require("firebase-functions/v2/scheduler");
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const BATCH_SIZE = 500;
async function handleCleanupExpiredInvites(deps) {
    const cutoff = Date.now() - SEVEN_DAYS_MS;
    const expiredIds = await deps.getExpiredInvites(cutoff);
    // Process in batches to avoid overloading Firestore
    for (let i = 0; i < expiredIds.length; i += BATCH_SIZE) {
        const batch = expiredIds.slice(i, i + BATCH_SIZE);
        await Promise.all(batch.map((id) => deps.deleteInvite(id)));
    }
}
// ─── Cloud Function export ────────────────────────────────────────────────────
exports.cleanupExpiredInvites = (0, scheduler_1.onSchedule)({ schedule: '0 3 * * *', timeZone: 'UTC' }, async () => {
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
});
//# sourceMappingURL=cleanupExpiredInvites.js.map