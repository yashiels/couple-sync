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
exports.onBlockWrite = void 0;
exports.handleBlockWrite = handleBlockWrite;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const overlap_1 = require("./lib/overlap");
async function handleBlockWrite(coupleId, deps) {
    var _a, _b;
    const couple = await deps.getCouple(coupleId);
    if (!couple)
        return;
    const allBlocks = await deps.getBlocks(coupleId);
    const blocksA = allBlocks.filter((b) => b.userId === couple.userAUid);
    const blocksB = allBlocks.filter((b) => b.userId === couple.userBUid);
    const hashA = (0, overlap_1.computeBlockHash)(blocksA);
    const hashB = (0, overlap_1.computeBlockHash)(blocksB);
    // Skip recomputation if nothing has changed
    const existing = await deps.getCurrentOverlap(coupleId);
    if (existing && existing.blockHashA === hashA && existing.blockHashB === hashB)
        return;
    const [userA, userB] = await Promise.all([
        deps.getUser(couple.userAUid),
        deps.getUser(couple.userBUid),
    ]);
    const timezoneA = (_a = userA === null || userA === void 0 ? void 0 : userA.timezone) !== null && _a !== void 0 ? _a : 'UTC';
    const timezoneB = (_b = userB === null || userB === void 0 ? void 0 : userB.timezone) !== null && _b !== void 0 ? _b : 'UTC';
    const windows = (0, overlap_1.computeOverlap)(blocksA, blocksB, timezoneA, timezoneB, Date.now(), { showLateNightWindows: (userA === null || userA === void 0 ? void 0 : userA.showLateNightWindows) === true }, { showLateNightWindows: (userB === null || userB === void 0 ? void 0 : userB.showLateNightWindows) === true });
    await deps.saveOverlap(coupleId, {
        windows,
        computedAt: Date.now(),
        blockHashA: hashA,
        blockHashB: hashB,
    });
}
// ─── Cloud Function export ────────────────────────────────────────────────────
exports.onBlockWrite = (0, firestore_1.onDocumentWritten)({ document: 'timeblocks/{coupleId}/blocks/{blockId}', region: 'us-central1', memory: '512MiB', timeoutSeconds: 120 }, async (event) => {
    const db = admin.firestore();
    const { coupleId } = event.params;
    await handleBlockWrite(coupleId, {
        getCouple: async (id) => {
            const snap = await db.collection('couples').doc(id).get();
            return snap.exists ? snap.data() : null;
        },
        getUser: async (uid) => {
            const snap = await db.collection('users').doc(uid).get();
            if (!snap.exists)
                return null;
            const d = snap.data();
            return { timezone: d.timezone, showLateNightWindows: d.showLateNightWindows };
        },
        getBlocks: async (cId) => {
            const snap = await db.collection('timeblocks').doc(cId).collection('blocks').get();
            return snap.docs.map((d) => (Object.assign({ id: d.id }, d.data())));
        },
        getCurrentOverlap: async (cId) => {
            const snap = await db
                .collection('overlaps').doc(cId).collection('windows').doc('latest').get();
            return snap.exists
                ? snap.data()
                : null;
        },
        saveOverlap: async (cId, result) => {
            await db
                .collection('overlaps').doc(cId).collection('windows').doc('latest').set(result);
        },
    });
});
//# sourceMappingURL=onBlockWrite.js.map