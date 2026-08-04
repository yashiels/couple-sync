import admin from 'firebase-admin';
import { config } from './config.js';

// cert() throws on a malformed key, and that throw is deliberately uncaught: a container with bad
// credentials must not boot.
const app = admin.initializeApp({
  credential: admin.credential.cert({
    projectId: config.serviceAccount.projectId,
    clientEmail: config.serviceAccount.clientEmail,
    privateKey: config.serviceAccount.privateKey,
  }),
  projectId: config.serviceAccount.projectId,
});

export function verifyIdToken(token: string): Promise<admin.auth.DecodedIdToken> {
  return admin.auth(app).verifyIdToken(token);
}

export function messaging(): admin.messaging.Messaging {
  return admin.messaging(app);
}

// Proves the private key can actually mint an access token, so a wrong-but-parseable key fails at
// boot instead of on the first request.
export async function assertCredentials(): Promise<void> {
  await app.options.credential!.getAccessToken();
}
