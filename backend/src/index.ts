import Fastify from 'fastify';
import websocket from '@fastify/websocket';
import cron from 'node-cron';
import pino from 'pino';
import { getConfig } from './config.js';
import { getPool, endPool } from './db.js';
import { initFirebaseAdmin } from './firebase.js';
import { authRoutes } from './routes/auth.js';
import { syncRoutes } from './routes/sync.js';
import { blockRoutes } from './routes/blocks.js';
import { userRoutes } from './routes/users.js';
import { coupleRoutes } from './routes/couples.js';

const log = pino({ name: 'api' });

async function bootstrap() {
  const config = getConfig();
  log.info({ domain: config.domain, port: config.port }, 'Starting Couple Sync backend');

  // Init Postgres pool (lazy — connection happens on first query).
  const pool = getPool();
  try {
    const res = await pool.query('SELECT 1 AS ok');
    if (res.rows[0]?.ok !== 1) throw new Error('unexpected SELECT 1 result');
    log.info('Postgres reachable');
  } catch (err) {
    log.error({ err }, 'Postgres health check failed — continuing anyway');
  }

  // Init Firebase Admin (Auth verify + FCM). Soft-fail if misconfigured so
  // the skeleton still boots for dev; routes will hard-fail on use.
  initFirebaseAdmin();

  const app = Fastify({ logger: log });

  await app.register(websocket);

  app.get('/health', async () => ({ status: 'ok', time: Date.now() }));

  // REST auth routes: /auth/verify, /auth/fcm-token
  await app.register(authRoutes);

  // WebSocket sync route: /sync (upgraded)
  await app.register(syncRoutes);

  // REST: block CRUD + WS broadcast (V3).
  await app.register(blockRoutes);
  // REST: user profile GET/PATCH (V3).
  await app.register(userRoutes);
  // REST: couple GET (V3).
  await app.register(coupleRoutes);

  // node-cron placeholder — cleanupExpiredInvites port comes later.
  const cleanupJob = cron.schedule('0 * * * *', () => {
    log.debug('cleanup tick (placeholder)');
  });
  cleanupJob.start();

  const shutdown = async (signal: string) => {
    log.info({ signal }, 'Shutting down');
    cleanupJob.stop();
    await app.close();
    await endPool();
    process.exit(0);
  };
  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));

  try {
    await app.listen({ port: config.port, host: '0.0.0.0' });
    log.info({ port: config.port }, 'Listening');
  } catch (err) {
    log.error({ err }, 'Failed to listen');
    process.exit(1);
  }
}

bootstrap().catch((err) => {
  log.error({ err }, 'Fatal bootstrap error');
  process.exit(1);
});
