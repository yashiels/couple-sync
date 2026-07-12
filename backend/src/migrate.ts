import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getPool } from './db.js';
import { getConfig } from './config.js';
import pino from 'pino';

const log = pino({ name: 'migrate' });

const __dirname = dirname(fileURLToPath(import.meta.url));

export async function runMigrations(): Promise<void> {
  // Force config load so missing env fails fast.
  getConfig();
  const pool = getPool();
  const dir = join(__dirname, 'migrations');
  // Run every *.sql file in lexical order so new migrations aren't silently
  // dropped (previously this hardcoded 001_init.sql only). Each migration is
  // idempotent (CREATE TABLE IF NOT EXISTS / ALTER ... SET DEFAULT).
  const files = readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort();
  for (const file of files) {
    const sqlPath = join(dir, file);
    const sql = readFileSync(sqlPath, 'utf8');
    log.info({ sqlPath }, 'Running migration');
    await pool.query(sql);
  }
  log.info({ count: files.length }, 'Migrations complete');
}

runMigrations()
  .then(() => process.exit(0))
  .catch((err) => {
    log.error({ err }, 'Migration failed');
    process.exit(1);
  });
