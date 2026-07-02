import type { FastifyRequest } from 'fastify';
import admin from 'firebase-admin';
import { getAuth } from './firebase.js';

/** Firebase ID token — use the SDK's type, not a hand-rolled subset. */
export type DecodedIdToken = admin.auth.DecodedIdToken;

export class UnauthorizedError extends Error {
  statusCode = 401 as const;
  constructor(message: string) {
    super(message);
    this.name = 'UnauthorizedError';
  }
}

/**
 * Extract + verify a Firebase ID token from the request.
 *
 * Accepts either:
 *   - `Authorization: Bearer <token>` header (REST routes), or
 *   - `?token=<token>` query param (WebSocket handshake, where browsers
 *     cannot set headers on the WS upgrade).
 *
 * Throws UnauthorizedError (statusCode 401) on missing/invalid token.
 */
export async function authenticate(request: FastifyRequest): Promise<DecodedIdToken> {
  const token = extractToken(request);
  if (!token) {
    throw new UnauthorizedError('Missing bearer token');
  }
  try {
    return await getAuth().verifyIdToken(token);
  } catch (err) {
    throw new UnauthorizedError(
      `Invalid Firebase ID token: ${err instanceof Error ? err.message : String(err)}`
    );
  }
}

function extractToken(request: FastifyRequest): string | null {
  // Header first (REST).
  const header = request.headers.authorization;
  if (header && /^Bearer\s+/i.test(header)) {
    const token = header.replace(/^Bearer\s+/i, '').trim();
    if (token) return token;
  }
  // Query fallback (WS handshake — browsers can't set headers on upgrade).
  const queryToken = (request.query as Record<string, string> | undefined)?.token;
  if (queryToken && queryToken.trim() !== '') return queryToken.trim();
  return null;
}

/**
 * Fastify preHandler that attaches the decoded token to `request.user`.
 * Use on REST routes that require auth.
 */
export async function authPreHandler(request: FastifyRequest): Promise<void> {
  (request as any).user = await authenticate(request);
}
