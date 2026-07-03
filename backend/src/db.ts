import pg from 'pg';
import { getConfig } from './config.js';

const { Pool } = pg;

let pool: pg.Pool | null = null;

export function getPool(): pg.Pool {
  if (pool) return pool;
  const config = getConfig();
  pool = new Pool({ connectionString: config.databaseUrl });
  return pool;
}

export async function query<T extends pg.QueryResultRow = any>(
  text: string,
  params?: readonly unknown[]
): Promise<pg.QueryResult<T>> {
  return getPool().query<T>(text, params as any);
}

export async function endPool(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = null;
  }
}
