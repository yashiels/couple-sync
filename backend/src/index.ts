import cors from '@fastify/cors';
import Fastify, { type FastifyInstance } from 'fastify';
import { config } from './config.js';
import { assertReachable } from './db.js';
import { assertCredentials } from './firebase.js';
import { registerErrorHandler } from './http.js';
import authRoutes from './routes/auth.js';
import blocksRoutes from './routes/blocks.js';
import couplesRoutes from './routes/couples.js';
import invitesRoutes from './routes/invites.js';
import overlapsRoutes from './routes/overlaps.js';
import usersRoutes from './routes/users.js';

/**
 * Every authenticated route lives in one of these plugins, and the list is exported so
 * guards.matrix.test.ts can enumerate the live route tree from the same source start() registers
 * from — a route added to a plugin without being added to that test's table then fails CI.
 * /health (public) and Task 8's /admin/cleanup (ADMIN_TOKEN) are registered directly instead.
 */
export const routePlugins = [
  authRoutes,
  usersRoutes,
  blocksRoutes,
  overlapsRoutes,
  couplesRoutes,
  invitesRoutes,
];

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
  for (const routes of routePlugins) {
    await app.register(routes);
  }
  // The WS /sync and /admin/cleanup land here in Task 8

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
