import cors from '@fastify/cors';
import Fastify, { type FastifyInstance } from 'fastify';
import { config } from './config.js';
import { assertReachable } from './db.js';
import { assertCredentials } from './firebase.js';
import { registerErrorHandler } from './http.js';
import authRoutes from './routes/auth.js';
import couplesRoutes from './routes/couples.js';
import invitesRoutes from './routes/invites.js';
import usersRoutes from './routes/users.js';

/**
 * Order matters: both probes run before anything can listen, and both reject rather than warn.
 * The previous build warned and booted, so a misconfigured container passed its healthcheck while
 * 401-ing every authenticated request.
 */
export async function start(): Promise<FastifyInstance> {
  await assertReachable();
  await assertCredentials();

  const app = Fastify({ logger: true });
  registerErrorHandler(app);
  await app.register(cors, { origin: config.corsOrigins });
  app.get('/health', async () => ({ status: 'ok', time: Date.now() }));
  // One register() per plugin, because each adds its own requireAuth preHandler and Fastify scopes
  // a hook to the plugin that added it. /health above stays unauthenticated.
  for (const routes of [authRoutes, usersRoutes, couplesRoutes, invitesRoutes]) {
    await app.register(routes);
  }
  // blocks, overlaps and the WS /sync land here in Tasks 7-8

  await app.listen({ port: config.port, host: '0.0.0.0' });
  return app;
}

/** The entrypoint. A failed probe is a non-zero exit, never a degraded service. */
export async function main(): Promise<void> {
  try {
    await start();
  } catch (err) {
    console.error('[boot] failed', err);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) void main();
