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
exports.onUserPrefsWrite = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const firebase_functions_1 = require("firebase-functions");
const overlap_1 = require("./lib/overlap");
/**
 * Recomputes the couple's overlap windows when a user toggles a preference
 * that affects windowing (currently: showLateNightWindows).
 */
exports.onUserPrefsWrite = (0, firestore_1.onDocumentUpdated)({ document: 'users/{uid}', region: 'us-central1', memory: '512MiB', timeoutSeconds: 120 }, async (event) => {
    var _a, _b, _c, _d, _e, _f;
    const before = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const after = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    if (!before || !after)
        return;
    const prefChanged = ((_c = before.showLateNightWindows) !== null && _c !== void 0 ? _c : false) !== ((_d = after.showLateNightWindows) !== null && _d !== void 0 ? _d : false);
    if (!prefChanged)
        return;
    const coupleId = after.coupleId;
    if (!coupleId)
        return;
    const db = admin.firestore();
    const coupleSnap = await db.collection('couples').doc(coupleId).get();
    if (!coupleSnap.exists)
        return;
    const couple = coupleSnap.data();
    const blocksSnap = await db
        .collection('timeblocks').doc(coupleId).collection('blocks').get();
    const allBlocks = blocksSnap.docs.map((d) => (Object.assign({ id: d.id }, d.data())));
    const blocksA = allBlocks.filter((b) => b.userId === couple.userAUid);
    const blocksB = allBlocks.filter((b) => b.userId === couple.userBUid);
    // The triggering user's data is already in the event — avoid a redundant read.
    const triggeringUid = event.params.uid;
    if (triggeringUid !== couple.userAUid && triggeringUid !== couple.userBUid) {
        firebase_functions_1.logger.warn(`onUserPrefsWrite: uid ${triggeringUid} is not in couple ${coupleId}`);
        return;
    }
    const triggeringData = after;
    const otherUid = triggeringUid === couple.userAUid ? couple.userBUid : couple.userAUid;
    const otherSnap = await db.collection('users').doc(otherUid).get();
    const otherData = otherSnap.data();
    const [userA, userB] = triggeringUid === couple.userAUid
        ? [triggeringData, otherData]
        : [otherData, triggeringData];
    const windows = (0, overlap_1.computeOverlap)(blocksA, blocksB, (_e = userA === null || userA === void 0 ? void 0 : userA.timezone) !== null && _e !== void 0 ? _e : 'UTC', (_f = userB === null || userB === void 0 ? void 0 : userB.timezone) !== null && _f !== void 0 ? _f : 'UTC', Date.now(), { showLateNightWindows: (userA === null || userA === void 0 ? void 0 : userA.showLateNightWindows) === true }, { showLateNightWindows: (userB === null || userB === void 0 ? void 0 : userB.showLateNightWindows) === true });
    await db
        .collection('overlaps').doc(coupleId).collection('windows').doc('latest').set({
        windows,
        computedAt: Date.now(),
        blockHashA: (0, overlap_1.computeBlockHash)(blocksA),
        blockHashB: (0, overlap_1.computeBlockHash)(blocksB),
    });
});
//# sourceMappingURL=onUserPrefsWrite.js.map