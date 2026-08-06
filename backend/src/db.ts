import pg from 'pg';
import { config } from './config.js';

// BIGINT columns are all UTC epoch millis, which fit in a JS double. Parse them as numbers so the
// wire format is `number` end to end instead of pg's default string.
pg.types.setTypeParser(pg.types.builtins.INT8, (v) => Number(v));

export const pool = new pg.Pool({ connectionString: config.databaseUrl, max: 10 });

export type Querier = {
  query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>;
};

export async function query<T = Record<string, unknown>>(
  sql: string,
  params: unknown[] = [],
): Promise<T[]> {
  const res = await pool.query(sql, params);
  return res.rows as T[];
}

export async function withTx<T>(fn: (q: Querier) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const out = await fn({
      query: async <R>(sql: string, params: unknown[] = []) =>
        (await client.query(sql, params)).rows as R[],
    });
    await client.query('COMMIT');
    return out;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

// Boot gate. A container that cannot reach Postgres must crash, not report healthy and 500 later.
export async function assertReachable(): Promise<void> {
  await query('SELECT 1');
}
