import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth, type DecodedIdToken } from 'firebase-admin/auth';
import { getMessaging, type BaseMessage } from 'firebase-admin/messaging';
import { config } from './config.js';

// cert() throws on a structurally broken service account, and that throw is deliberately uncaught:
// a container with bad credentials must not boot.
const credential = cert(config.firebaseServiceAccount);
const app = initializeApp({ credential, projectId: config.firebaseProjectId });

/** firebase-admin's full claim set. Never narrow it — req.claims is typed DecodedIdToken and
 *  routes read email/name/picture off it. */
export function verifyIdToken(token: string): Promise<DecodedIdToken> {
  return getAuth(app).verifyIdToken(token);
}

/**
 * Boot probe. Fatal, never a warning.
 *
 * Do NOT probe with verifyIdToken('not-a-token'): firebase-admin rejects a malformed JWT while
 * *decoding* it, before the credential is ever used, so that probe passes with a completely bogus
 * private key — the exact false confidence the previous build shipped. getAccessToken() mints a
 * real OAuth2 access token from Google, so it fails on an unusable key.
 */
export async function assertCredentials(): Promise<void> {
  // Checked first because it needs no network. Right key, wrong project is a silent
  // misconfiguration in which every token verification fails on audience.
  if (config.firebaseServiceAccount.projectId !== config.firebaseProjectId) {
    throw new Error(
      `[firebase] FIREBASE_PROJECT_ID (${config.firebaseProjectId}) does not match the service account projectId (${String(config.firebaseServiceAccount.projectId)})`,
    );
  }
  await credential.getAccessToken();
}

/** One message per token, so one dead token cannot fail the batch. errorCode is null on success. */
export async function sendEach(
  tokens: string[],
  payload: BaseMessage,
): Promise<{ token: string; errorCode: string | null }[]> {
  if (tokens.length === 0) return [];
  const res = await getMessaging(app).sendEach(tokens.map((token) => ({ ...payload, token })));
  return res.responses.map((r, i) => ({ token: tokens[i]!, errorCode: r.error?.code ?? null }));
}
