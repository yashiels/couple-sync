// Env validation. Every problem here is a boot crash, never a warning: the previous build
// console.warn'ed on bad Firebase credentials and then booted "healthy" while 401-ing every
// request. Fail loud, fail at start.

function required(name: string): string {
  const v = process.env[name]?.trim();
  if (!v) throw new Error(`[config] missing required env var ${name}`);
  return v;
}

function parseCorsOrigins(): string[] {
  // No default, and '*' is refused outright. A wildcard here would let any web page drive the API
  // with a stolen ID token.
  const raw = required('CORS_ORIGINS');
  const origins = raw
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (origins.length === 0) throw new Error('[config] CORS_ORIGINS is empty');
  if (origins.includes('*')) throw new Error('[config] CORS_ORIGINS must not be "*"');
  return origins;
}

export type ServiceAccount = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

function parseServiceAccount(): ServiceAccount {
  // Accepts raw JSON or base64-encoded JSON (base64 survives every env-var UI ever built).
  const raw = required('FIREBASE_SERVICE_ACCOUNT');
  const json = raw.startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8');
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(json) as Record<string, unknown>;
  } catch {
    throw new Error('[config] FIREBASE_SERVICE_ACCOUNT is not valid JSON (raw or base64)');
  }
  const projectId = (parsed['project_id'] ?? parsed['projectId']) as string | undefined;
  const clientEmail = (parsed['client_email'] ?? parsed['clientEmail']) as string | undefined;
  const privateKey = (parsed['private_key'] ?? parsed['privateKey']) as string | undefined;
  if (!projectId || !clientEmail || !privateKey) {
    throw new Error('[config] FIREBASE_SERVICE_ACCOUNT missing project_id/client_email/private_key');
  }
  return { projectId, clientEmail, privateKey: privateKey.replace(/\\n/g, '\n') };
}

export const config = {
  port: Number(process.env.PORT ?? 3000),
  host: process.env.HOST ?? '0.0.0.0',
  databaseUrl: required('DATABASE_URL'),
  corsOrigins: parseCorsOrigins(),
  // Unset is legal; admin routes answer 503 instead of silently running unauthenticated.
  adminToken: process.env.ADMIN_TOKEN?.trim() || null,
  serviceAccount: parseServiceAccount(),
  logLevel: process.env.LOG_LEVEL ?? 'info',
};
