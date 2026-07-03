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
exports.onOverlapWrite = exports.INVALID_TOKEN_CODES = void 0;
exports.filterInvalidFcmTokens = filterInvalidFcmTokens;
exports.validateWindows = validateWindows;
exports.handleOnOverlapWrite = handleOnOverlapWrite;
const luxon_1 = require("luxon");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const firebase_functions_1 = require("firebase-functions");
// ─── Module-scope constants ───────────────────────────────────────────────────
exports.INVALID_TOKEN_CODES = [
    'messaging/invalid-registration-token',
    'messaging/registration-token-not-registered',
];
/**
 * Given a list of tokens and the per-message responses from sendEachForMulticast,
 * returns only the tokens that should be pruned (i.e. those with a hard-invalid code).
 * Transient errors (quota exceeded, internal, etc.) are logged but NOT pruned.
 */
function filterInvalidFcmTokens(tokens, responses) {
    var _a, _b;
    const invalid = [];
    for (const [i, result] of responses.entries()) {
        if (!result.success) {
            const code = (_b = (_a = result.error) === null || _a === void 0 ? void 0 : _a.code) !== null && _b !== void 0 ? _b : '';
            if (exports.INVALID_TOKEN_CODES.includes(code)) {
                invalid.push(tokens[i]);
            }
            else {
                firebase_functions_1.logger.warn(`[onOverlapWrite] Transient FCM error for token[${i}], code=${code} — not pruning`);
            }
        }
    }
    return invalid;
}
function formatOverlapBody(window) {
    const dt = luxon_1.DateTime.fromMillis(window.startUtc, { zone: 'UTC' });
    const hours = (window.durationMinutes / 60).toFixed(1).replace(/\.0$/, '');
    return `${hours}h free together on ${dt.toFormat('EEE, MMM d')}`;
}
function validateWindows(input) {
    const out = [];
    for (const w of input) {
        if (typeof w.startUtc !== 'number' || !Number.isInteger(w.startUtc) ||
            typeof w.endUtc !== 'number' || !Number.isInteger(w.endUtc) ||
            typeof w.durationMinutes !== 'number' || !Number.isInteger(w.durationMinutes) ||
            typeof w.score !== 'number' || !Number.isFinite(w.score) ||
            typeof w.reasonableBoth !== 'boolean') {
            throw new Error('invalid window shape');
        }
        if (!(w.durationMinutes > 0 && w.durationMinutes <= 1560)) {
            throw new Error('durationMinutes out of bounds');
        }
        if (!(w.startUtc < w.endUtc)) {
            throw new Error('startUtc must be < endUtc');
        }
        if (Math.abs((w.endUtc - w.startUtc) - w.durationMinutes * 60000) > 1000) {
            throw new Error('durationMinutes does not match start/end');
        }
        out.push(w);
    }
    return out;
}
async function handleOnOverlapWrite(coupleId, windows, deps, computedBy) {
    let valid;
    try {
        valid = validateWindows(windows);
    }
    catch (e) {
        firebase_functions_1.logger.warn(`[onOverlapWrite] rejected malformed windows: ${e.message}`);
        return;
    }
    if (valid.length === 0)
        return;
    const couple = await deps.getCouple(coupleId);
    if (!couple)
        return;
    const targets = [couple.userAUid, couple.userBUid].filter((uid) => uid !== computedBy);
    const tokensPerUid = await Promise.all(targets.map(async (uid) => [uid, await deps.getFcmTokens(uid)]));
    const nextWindow = valid.reduce((best, w) => (w.startUtc < best.startUtc ? w : best));
    const notification = {
        title: 'You have free time together!',
        body: formatOverlapBody(nextWindow),
        data: { coupleId },
    };
    for (const [uid, tokens] of tokensPerUid) {
        if (tokens.length === 0)
            continue;
        const invalidTokens = await deps.sendNotification(tokens, notification);
        if (invalidTokens.length > 0) {
            const validTokens = tokens.filter((t) => !invalidTokens.includes(t));
            await deps.updateFcmTokens(uid, validTokens);
        }
    }
}
// ─── Cloud Function export ────────────────────────────────────────────────────
exports.onOverlapWrite = (0, firestore_1.onDocumentWritten)({ document: 'overlaps/{coupleId}/windows/latest', region: 'us-central1' }, async (event) => {
    var _a, _b;
    const db = admin.firestore();
    const messaging = admin.messaging();
    const { coupleId } = event.params;
    const after = (_a = event.data) === null || _a === void 0 ? void 0 : _a.after;
    const overlapResult = after === null || after === void 0 ? void 0 : after.data();
    const windows = (_b = overlapResult === null || overlapResult === void 0 ? void 0 : overlapResult.windows) !== null && _b !== void 0 ? _b : [];
    const computedBy = overlapResult === null || overlapResult === void 0 ? void 0 : overlapResult.computedBy;
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
            return filterInvalidFcmTokens(tokens, response.responses);
        },
        updateFcmTokens: async (uid, validTokens) => {
            await db.collection('users').doc(uid).update({ fcmTokens: validTokens });
        },
    }, computedBy);
});
//# sourceMappingURL=onOverlapWrite.js.map