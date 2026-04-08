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
exports.onOverlapWrite = void 0;
exports.handleOnOverlapWrite = handleOnOverlapWrite;
const luxon_1 = require("luxon");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
function formatOverlapBody(window) {
    const dt = luxon_1.DateTime.fromMillis(window.startUtc, { zone: 'UTC' });
    const hours = (window.durationMinutes / 60).toFixed(1).replace(/\.0$/, '');
    return `${hours}h free together on ${dt.toFormat('EEE, MMM d')}`;
}
async function handleOnOverlapWrite(coupleId, windows, deps) {
    if (windows.length === 0)
        return;
    const couple = await deps.getCouple(coupleId);
    if (!couple)
        return;
    const [tokensA, tokensB] = await Promise.all([
        deps.getFcmTokens(couple.userAUid),
        deps.getFcmTokens(couple.userBUid),
    ]);
    // Pick next upcoming window for the notification body
    const nextWindow = windows.reduce((best, w) => (w.startUtc < best.startUtc ? w : best));
    const notification = {
        title: "You have free time together!",
        body: formatOverlapBody(nextWindow),
        data: { coupleId },
    };
    const sendIfTokens = async (uid, tokens) => {
        if (tokens.length === 0)
            return;
        const invalidTokens = await deps.sendNotification(tokens, notification);
        if (invalidTokens.length > 0) {
            const valid = tokens.filter((t) => !invalidTokens.includes(t));
            await deps.updateFcmTokens(uid, valid);
        }
    };
    await Promise.all([
        sendIfTokens(couple.userAUid, tokensA),
        sendIfTokens(couple.userBUid, tokensB),
    ]);
}
// ─── Cloud Function export ────────────────────────────────────────────────────
exports.onOverlapWrite = (0, firestore_1.onDocumentWritten)('overlaps/{coupleId}/windows/latest', async (event) => {
    var _a, _b;
    const db = admin.firestore();
    const messaging = admin.messaging();
    const { coupleId } = event.params;
    const after = (_a = event.data) === null || _a === void 0 ? void 0 : _a.after;
    const overlapResult = after === null || after === void 0 ? void 0 : after.data();
    const windows = (_b = overlapResult === null || overlapResult === void 0 ? void 0 : overlapResult.windows) !== null && _b !== void 0 ? _b : [];
    await handleOnOverlapWrite(coupleId, windows, {
        getCouple: async (id) => {
            const snap = await db.collection('couples').doc(id).get();
            return snap.exists ? snap.data() : null;
        },
        getFcmTokens: async (uid) => {
            var _a;
            const snap = await db.collection('users').doc(uid).get();
            return snap.exists ? ((_a = snap.data().fcmTokens) !== null && _a !== void 0 ? _a : []) : [];
        },
        sendNotification: async (tokens, notif) => {
            const response = await messaging.sendEachForMulticast({
                tokens,
                notification: { title: notif.title, body: notif.body },
                data: notif.data,
            });
            const invalid = [];
            response.responses.forEach((r, idx) => {
                if (!r.success)
                    invalid.push(tokens[idx]);
            });
            return invalid;
        },
        updateFcmTokens: async (uid, validTokens) => {
            await db.collection('users').doc(uid).update({ fcmTokens: validTokens });
        },
    });
});
//# sourceMappingURL=onOverlapWrite.js.map