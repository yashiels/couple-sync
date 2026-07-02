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

export interface Config {
  databaseUrl: string;
  firebaseProjectId: string;
  firebaseServiceAccountJson: string;
  domain: string;
  port: number;
  adminToken: string | null;
}

let cached: Config | null = null;

export function loadConfig(): Config {
  if (cached) return cached;
  cached = {
    databaseUrl: required('DATABASE_URL'),
    firebaseProjectId: required('FIREBASE_PROJECT_ID'),
    firebaseServiceAccountJson: required('FIREBASE_SERVICE_ACCOUNT_JSON'),
    domain: optional('DOMAIN', 'api.example.com'),
    port: parseIntOrDefault('PORT', 3000),
    // Optional shared secret guarding POST /admin/* endpoints. When unset,
    // admin routes are disabled (respond 503). Not the same as Firebase auth
    // — this is a simple ops escape hatch for manual cron triggers.
    adminToken: optional('ADMIN_TOKEN', ''),
  };
  return cached;
}

export function getConfig(): Config {
  if (!cached) return loadConfig();
  return cached;
}
