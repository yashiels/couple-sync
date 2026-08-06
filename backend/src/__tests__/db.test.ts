import pg from 'pg';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// config.ts demands real Firebase credentials and CORS_ORIGINS at import, so it is mocked.
vi.mock('../config.js', () => ({
  config: { databaseUrl: 'postgres://postgres@127.0.0.1:1/none' },
}));

// Importing db.ts is what registers the int8 parser, so the import must happen before the assertion.
const { pool, withTx } = await import('../db.js');

function fakeClient() {
  return {
    query: vi.fn<(sql: string, params?: unknown[]) => Promise<{ rows: unknown[] }>>().mockResolvedValue({ rows: [] }),
    release: vi.fn(),
  };
}

describe('db', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('parses BIGINT as a number, not a string', () => {
    // Without this, every *_utc column arrives as "1712345678000" while wire.ts declares it a
    // number: it type-checks and is wrong.
    const parse = pg.types.getTypeParser(pg.types.builtins.INT8) as (v: string) => unknown;
    const parsed = parse('1712345678000');
    expect(typeof parsed).toBe('number');
    expect(parsed).toBe(1712345678000);
  });

  it('withTx commits and releases the client on the success path', async () => {
    const client = fakeClient();
    vi.spyOn(pool, 'connect').mockResolvedValue(client as never);

    const out = await withTx(async (q) => {
      await q.query('SELECT 1', [7]);
      return 'ok';
    });

    expect(out).toBe('ok');
    // The Querier is bound to the one client, so the statement really is inside the transaction.
    expect(client.query.mock.calls.map((c) => c[0])).toEqual(['BEGIN', 'SELECT 1', 'COMMIT']);
    expect(client.query).toHaveBeenCalledWith('SELECT 1', [7]);
    expect(client.release).toHaveBeenCalledTimes(1);
  });

  it('withTx rolls back and rethrows when the callback throws', async () => {
    const client = fakeClient();
    vi.spyOn(pool, 'connect').mockResolvedValue(client as never);

    await expect(
      withTx(async () => {
        throw new Error('boom');
      }),
    ).rejects.toThrow('boom');

    const sql = client.query.mock.calls.map((c) => c[0]);
    expect(sql).toEqual(['BEGIN', 'ROLLBACK']);
    expect(sql).not.toContain('COMMIT');
  });

  it('withTx releases the client on the error path too', async () => {
    const client = fakeClient();
    vi.spyOn(pool, 'connect').mockResolvedValue(client as never);

    await expect(withTx(async () => Promise.reject(new Error('boom')))).rejects.toThrow('boom');
    expect(client.release).toHaveBeenCalledTimes(1);
  });
});
