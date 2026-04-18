import * as admin from 'firebase-admin';

// Initialize Firebase Admin SDK once at the entry point
if (!admin.apps.length) {
  admin.initializeApp();
}

export { onBlockWrite } from './onBlockWrite';
export { onOverlapWrite } from './onOverlapWrite';
export { onInviteCreate } from './onInviteCreate';
export { redeemInvite } from './redeemInvite';
export { cleanupExpiredInvites } from './cleanupExpiredInvites';
export { onUserPrefsWrite } from './onUserPrefsWrite';
