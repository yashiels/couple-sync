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
exports.cleanupExpiredInvites = exports.redeemInvite = exports.onInviteCreate = exports.onOverlapWrite = exports.onBlockWrite = void 0;
const admin = __importStar(require("firebase-admin"));
// Initialize Firebase Admin SDK once at the entry point
if (!admin.apps.length) {
    admin.initializeApp();
}
var onBlockWrite_1 = require("./onBlockWrite");
Object.defineProperty(exports, "onBlockWrite", { enumerable: true, get: function () { return onBlockWrite_1.onBlockWrite; } });
var onOverlapWrite_1 = require("./onOverlapWrite");
Object.defineProperty(exports, "onOverlapWrite", { enumerable: true, get: function () { return onOverlapWrite_1.onOverlapWrite; } });
var onInviteCreate_1 = require("./onInviteCreate");
Object.defineProperty(exports, "onInviteCreate", { enumerable: true, get: function () { return onInviteCreate_1.onInviteCreate; } });
var redeemInvite_1 = require("./redeemInvite");
Object.defineProperty(exports, "redeemInvite", { enumerable: true, get: function () { return redeemInvite_1.redeemInvite; } });
var cleanupExpiredInvites_1 = require("./cleanupExpiredInvites");
Object.defineProperty(exports, "cleanupExpiredInvites", { enumerable: true, get: function () { return cleanupExpiredInvites_1.cleanupExpiredInvites; } });
//# sourceMappingURL=index.js.map