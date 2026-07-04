import dotenv from 'dotenv';

dotenv.config();

function required(name: string): string {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

function optional(name: string, fallback: string): string {
  const value = process.env[name];
  return value && value.trim() !== '' ? value : fallback;
}

function parseIntOrDefault(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  if (Number.isNaN(parsed)) {
    throw new Error(`Env var ${name} must be an integer, got: ${raw}`);
  }
  return parsed;
}

function parseCorsOrigins(raw: string): true | string[] {
  const value = raw.trim();
  if (value === '*' || value.toLowerCase() === 'true') {
    return true;
  }

  const origins = value
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);

  return origins.length > 0 ? origins : true;
}

export interface Config {
  databaseUrl: string;
  firebaseProjectId: string;
  firebaseServiceAccountJson: string;
  port: number;
  adminToken: string | null;
  corsOrigins: true | string[];
}

let cached: Config | null = null;

export function loadConfig(): Config {
  if (cached) return cached;
  cached = {
    databaseUrl: required('DATABASE_URL'),
    firebaseProjectId: required('FIREBASE_PROJECT_ID'),
    firebaseServiceAccountJson: required('FIREBASE_SERVICE_ACCOUNT_JSON'),
    port: parseIntOrDefault('PORT', 3000),
    // Optional shared secret guarding POST /admin/* endpoints. When unset,
    // admin routes are disabled (respond 503). Not the same as Firebase auth
    // — this is a simple ops escape hatch for manual cron triggers.
    adminToken: optional('ADMIN_TOKEN', ''),
    // Browser clients use Authorization headers rather than ambient cookies.
    // `*` is safe as a default, while Coolify prod can pin this to the web app
    // domain with a comma-separated allowlist.
    corsOrigins: parseCorsOrigins(optional('CORS_ORIGINS', '*')),
  };
  return cached;
}

export function getConfig(): Config {
  if (!cached) return loadConfig();
  return cached;
}
