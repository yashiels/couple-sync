import admin from 'firebase-admin';
import { getConfig } from './config.js';

let initialized = false;

/**
 * Initialise Firebase Admin SDK for Auth token verification + FCM.
 * Reads the service account JSON from the FIREBASE_SERVICE_ACCOUNT_JSON env
 * var (a stringified JSON key from the Firebase console).
 *
 * Soft-fails on missing/invalid config so the skeleton can boot in dev
 * without a live Firebase project; routes that need admin will throw on use.
 */
export function initFirebaseAdmin(): void {
  if (initialized) return;
  const config = getConfig();
  try {
    const serviceAccount = JSON.parse(config.firebaseServiceAccountJson);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: config.firebaseProjectId,
    });
    initialized = true;
  } catch (err) {
    // Don't crash the skeleton in dev. Auth/FCM routes will throw later.
    // eslint-disable-next-line no-console
    console.warn(
      '[firebase] Failed to init Firebase Admin from FIREBASE_SERVICE_ACCOUNT_JSON:',
      err instanceof Error ? err.message : String(err)
    );
  }
}

export function getAuth(): admin.auth.Auth {
  if (!initialized) initFirebaseAdmin();
  return admin.auth();
}

export function getMessaging(): admin.messaging.Messaging {
  if (!initialized) initFirebaseAdmin();
  return admin.messaging();
}
