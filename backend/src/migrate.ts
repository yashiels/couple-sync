import { readFileSync } from 'node:fs';
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
  const sqlPath = join(__dirname, 'migrations', '001_init.sql');
  const sql = readFileSync(sqlPath, 'utf8');
  log.info({ sqlPath }, 'Running migrations');
  await pool.query(sql);
  log.info('Migrations complete');
}

runMigrations()
  .then(() => process.exit(0))
  .catch((err) => {
    log.error({ err }, 'Migration failed');
    process.exit(1);
  });
