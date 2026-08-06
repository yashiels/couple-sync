import { readdir, readFile } from 'node:fs/promises';
import pg from 'pg';

// Resolves to src/migrations/ under tsx+vitest and dist/migrations/ after `pnpm build`
// (the build script copies the directory).
const migrationsDir = new URL('./migrations/', import.meta.url);

/**
 * Applies every migrations/*.sql in filename order, each in its own transaction.
 *
 * @param url explicit connection string. Required, and deliberately not read from config.ts:
 *   this module must not import config.ts or db.ts, because config.ts demands
 *   FIREBASE_SERVICE_ACCOUNT and CORS_ORIGINS — a migration job and the migration test would then
 *   need the whole server env. So it builds its own throwaway Client and closes it.
 */
export async function runMigrations(url: string): Promise<void> {
  const files = (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();
  const client = new pg.Client({ connectionString: url });
  await client.connect();
  try {
    for (const file of files) {
      await client.query('BEGIN');
      try {
        await client.query(await readFile(new URL(file, migrationsDir), 'utf8'));
        await client.query('COMMIT');
      } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw new Error(`[migrate] ${file} failed`, { cause: err });
      }
      console.log(`[migrate] applied ${file}`);
    }
  } finally {
    await client.end();
  }
}

// Standalone entrypoint: `node dist/migrate.js`.
if (import.meta.url === `file://${process.argv[1]}`) {
  const url = process.env['DATABASE_URL'];
  if (!url) {
    console.error('[migrate] DATABASE_URL required');
    process.exit(1);
  }
  runMigrations(url).catch((e: unknown) => {
    console.error(e);
    process.exit(1);
  });
}
