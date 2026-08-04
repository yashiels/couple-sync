import type { FastifyReply, FastifyRequest } from 'fastify';
import type { IncomingMessage } from 'node:http';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { verifyIdToken } from './firebase.js';

declare module 'fastify' {
  interface FastifyRequest {
    uid: string;
    tokenClaims: DecodedIdToken;
  }
}

// Bearer header is the normal path; `?token=` exists because not every WS client can set headers.
export function tokenFrom(req: { headers: IncomingMessage['headers']; url?: string }): string | null {
  const header = req.headers.authorization;
  if (header?.startsWith('Bearer ')) return header.slice(7).trim() || null;
  if (req.url) {
    const q = new URL(req.url, 'http://localhost').searchParams.get('token');
    if (q) return q.trim() || null;
  }
  return null;
}

export async function verifyRequestToken(req: {
  headers: IncomingMessage['headers'];
  url?: string;
}): Promise<string> {
  const token = tokenFrom(req);
  if (!token) throw new Error('missing token');
  const decoded = await verifyIdToken(token);
  return decoded.uid;
}

export async function requireAuth(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  const token = tokenFrom(req);
  if (!token) {
    await reply.code(401).send({ error: 'missing_token' });
    return;
  }
  try {
    const decoded = await verifyIdToken(token);
    req.uid = decoded.uid;
    req.tokenClaims = decoded;
  } catch {
    await reply.code(401).send({ error: 'invalid_token' });
  }
}
