// Env validation, once, at import. Every problem here is a boot crash, never a warning: the
// previous build console.warn'ed on bad Firebase credentials and then booted "healthy" while
// 401-ing every request. Fail loud, fail at start.
import type { ServiceAccount } from 'firebase-admin/app';

function required(name: string): string {
  const v = process.env[name]?.trim();
  if (!v) throw new Error(`[config] missing required env var ${name}`);
  return v;
}

function parsePort(): number {
  const raw = process.env['PORT']?.trim();
  if (!raw) return 3000;
  const port = Number(raw);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new Error(`[config] PORT is not a port number: ${raw}`);
  }
  return port;
}

function parseCorsOrigins(): string[] {
  // No default, and '*' is refused outright. A wildcard here would let any web page drive the API
  // with a stolen ID token.
  const origins = required('CORS_ORIGINS')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (origins.length === 0) throw new Error('[config] CORS_ORIGINS is empty');
  if (origins.includes('*')) throw new Error('[config] CORS_ORIGINS must not be "*"');
  return origins;
}

function parseServiceAccount(): ServiceAccount {
  // Google issues the key file in snake_case; firebase-admin's ServiceAccount type is camelCase.
  // This is the only place the two spellings meet — everything downstream, including the
  // projectId check in firebase.ts, reads camelCase.
  const raw = required('FIREBASE_SERVICE_ACCOUNT_JSON');
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    throw new Error('[config] FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON');
  }
  const projectId = parsed['project_id'] ?? parsed['projectId'];
  const clientEmail = parsed['client_email'] ?? parsed['clientEmail'];
  const privateKey = parsed['private_key'] ?? parsed['privateKey'];
  if (
    typeof projectId !== 'string' ||
    typeof clientEmail !== 'string' ||
    typeof privateKey !== 'string'
  ) {
    throw new Error(
      '[config] FIREBASE_SERVICE_ACCOUNT_JSON needs project_id, client_email and private_key',
    );
  }
  // Env-var panels that escape the value a second time leave literal backslash-n in the key.
  return { projectId, clientEmail, privateKey: privateKey.replace(/\\n/g, '\n') };
}

export const config = Object.freeze({
  port: parsePort(),
  databaseUrl: required('DATABASE_URL'),
  firebaseProjectId: required('FIREBASE_PROJECT_ID'),
  firebaseServiceAccount: parseServiceAccount(),
  corsOrigins: parseCorsOrigins(),
  // Unset is legal; admin routes answer 503 instead of silently running unauthenticated.
  adminToken: process.env['ADMIN_TOKEN']?.trim() || null,
});
