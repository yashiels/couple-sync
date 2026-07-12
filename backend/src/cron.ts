import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { timingSafeEqual } from 'node:crypto';
import cron from 'node-cron';
import type { ScheduledTask } from 'node-cron';
import type { Logger } from 'pino';
import { query } from './db.js';
import { getConfig } from './config.js';

/**
 * Cleanup job — port of functions/src/cleanupExpiredInvites.ts.
 *
 * The CF deleted invite docs older than 7 days. The V4 spec instead flips
 * pending+expired invites to status='expired' (so the row is preserved for
 * audit + idempotent-redeem guards). Runs daily at 03:00 UTC.
 */
export async function cleanupExpiredInvites(): Promise<number> {
  const now = Date.now();
  const res = await query(
    'UPDATE invites SET status = $1 WHERE status = $2 AND expires_at < $3',
    ['expired', 'pending', now]
  );
  return res.rowCount ?? 0;
}

/**
 * Register the daily cleanup cron. Returns the ScheduledTask so the caller
 * can stop it on shutdown.
 */
export function startCleanupCron(log?: Logger): ScheduledTask {
  const task = cron.schedule(
    '0 3 * * *',
    async () => {
      try {
        const count = await cleanupExpiredInvites();
        log?.info({ expired: count }, 'cleanupExpiredInvites tick');
      } catch (err) {
        log?.error({ err }, 'cleanupExpiredInvites failed');
      }
    },
    { timezone: 'UTC' }
  );
  task.start();
  return task;
}

/**
 * POST /admin/cleanup — manual trigger of the cleanup job, guarded by a
 * shared ADMIN_TOKEN env secret (Bearer header). Returns the count flipped.
 * Responds 503 if ADMIN_TOKEN is not configured.
 */
export const adminRoutes: FastifyPluginAsync = async (app) => {
  app.post('/admin/cleanup', async (request: FastifyRequest, reply: FastifyReply) => {
    const expected = getConfig().adminToken;
    if (!expected) {
      return reply.code(503).send({ error: 'unavailable', message: 'ADMIN_TOKEN not configured' });
    }
    const header = request.headers.authorization ?? '';
    const token = header.replace(/^Bearer\s+/i, '').trim();
    // Constant-time compare to avoid leaking the expected token length/value
    // via an early-return timing delta. Guard the length first —
    // timingSafeEqual throws on unequal-length Buffers.
    const a = Buffer.from(token);
    const b = Buffer.from(expected);
    const ok = a.length === b.length && timingSafeEqual(a, b);
    if (!token || !ok) {
      return reply.code(401).send({ error: 'unauthorized', message: 'Invalid admin token' });
    }
    try {
      const count = await cleanupExpiredInvites();
      return reply.code(200).send({ expired: count });
    } catch (err) {
      return reply.code(500).send({
        error: 'error',
        message: err instanceof Error ? err.message : 'Internal error',
      });
    }
  });
};

export default adminRoutes;
