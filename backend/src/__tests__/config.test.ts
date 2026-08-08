import { afterEach, describe, expect, it, vi } from 'vitest';

// config.ts validates at import time, so every case has to load it fresh with a stubbed env.
const SERVICE_ACCOUNT = JSON.stringify({
  project_id: 'test-project',
  client_email: 'sa@test-project.iam.gserviceaccount.com',
  private_key: 'fake-key-material-line-1\\nline-2\\n',
});

const BASE: Record<string, string | undefined> = {
  PORT: undefined,
  ADMIN_TOKEN: undefined,
  DATABASE_URL: 'postgres://postgres@localhost:5432/couple_sync',
  FIREBASE_PROJECT_ID: 'test-project',
  FIREBASE_SERVICE_ACCOUNT_JSON: SERVICE_ACCOUNT,
  CORS_ORIGINS: 'https://couple-sync.example.com',
};

async function load(overrides: Record<string, string | undefined> = {}) {
  vi.resetModules();
  for (const [k, v] of Object.entries({ ...BASE, ...overrides })) vi.stubEnv(k, v);
  return (await import('../config.js')).config;
}

afterEach(() => {
  vi.unstubAllEnvs();
});

describe('config', () => {
  it('throws when DATABASE_URL is unset', async () => {
    await expect(load({ DATABASE_URL: undefined })).rejects.toThrow(/DATABASE_URL/);
  });

  it('throws when FIREBASE_PROJECT_ID is unset', async () => {
    await expect(load({ FIREBASE_PROJECT_ID: undefined })).rejects.toThrow(/FIREBASE_PROJECT_ID/);
  });

  it('throws when the firebase service account env var is unset', async () => {
    await expect(load({ FIREBASE_SERVICE_ACCOUNT_JSON: undefined })).rejects.toThrow(
      /FIREBASE_SERVICE_ACCOUNT_JSON/,
    );
  });

  it('throws when the firebase service account env var is not valid JSON', async () => {
    await expect(load({ FIREBASE_SERVICE_ACCOUNT_JSON: '{not json' })).rejects.toThrow(
      /not valid JSON/,
    );
  });

  it('throws when the firebase service account is missing private_key', async () => {
    const partial = JSON.stringify({ project_id: 'p', client_email: 'e@p.example' });
    await expect(load({ FIREBASE_SERVICE_ACCOUNT_JSON: partial })).rejects.toThrow(/private_key/);
  });

  it('exposes the service account in firebase-admin camelCase', async () => {
    // The boot-time projectId check compares config.firebaseServiceAccount.projectId against
    // FIREBASE_PROJECT_ID, so a snake_case passthrough would compare undefined to a string.
    const config = await load();
    expect(config.firebaseServiceAccount).toEqual({
      projectId: 'test-project',
      clientEmail: 'sa@test-project.iam.gserviceaccount.com',
      // escaped newlines are unescaped — env panels that re-escape the key are common
      privateKey: 'fake-key-material-line-1\nline-2\n',
    });
  });

  it('throws when CORS_ORIGINS is unset', async () => {
    // Must NOT silently default to '*' — the previous build did.
    await expect(load({ CORS_ORIGINS: undefined })).rejects.toThrow(/CORS_ORIGINS/);
  });

  it('throws when CORS_ORIGINS is literally "*"', async () => {
    await expect(load({ CORS_ORIGINS: '*' })).rejects.toThrow(/CORS_ORIGINS must not be "\*"/);
  });

  it('throws when "*" is one entry in a CORS_ORIGINS list', async () => {
    await expect(load({ CORS_ORIGINS: 'https://a.example,*' })).rejects.toThrow(/must not be/);
  });

  it('parses CORS_ORIGINS into a trimmed array', async () => {
    const config = await load({ CORS_ORIGINS: ' https://a.example , https://b.example ,' });
    expect(config.corsOrigins).toEqual(['https://a.example', 'https://b.example']);
  });

  it('defaults port to 3000 and throws on a non-numeric PORT', async () => {
    expect((await load()).port).toBe(3000);
    expect((await load({ PORT: '8080' })).port).toBe(8080);
    await expect(load({ PORT: 'not-a-port' })).rejects.toThrow(/PORT/);
  });

  it('leaves adminToken null when the admin token env var is unset', async () => {
    expect((await load()).adminToken).toBeNull();
    expect((await load({ ADMIN_TOKEN: '  ' })).adminToken).toBeNull();
    expect((await load({ ADMIN_TOKEN: ' s3cret ' })).adminToken).toBe('s3cret');
  });

  it('is frozen', async () => {
    expect(Object.isFrozen(await load())).toBe(true);
  });
});
