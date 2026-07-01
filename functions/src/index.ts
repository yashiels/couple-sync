import * as admin from 'firebase-admin';

// Initialize Firebase Admin SDK once at the entry point
if (!admin.apps.length) {
  admin.initializeApp();
}

export { onOverlapWrite } from './onOverlapWrite';
export { onInviteCreate } from './onInviteCreate';
export { redeemInvite } from './redeemInvite';
export { unpairCouple } from './unpairCouple';
export { cleanupExpiredInvites } from './cleanupExpiredInvites';
