import type { preHandlerHookHandler } from 'fastify';
import type { DecodedIdToken } from 'firebase-admin/auth';
import type { IncomingMessage } from 'node:http';
import { verifyIdToken } from './firebase.js';
import { HttpError } from './http.js';

declare module 'fastify' {
  interface FastifyRequest {
    uid: string;
    /** The full claim set, not a narrowed subset — /auth/verify upserts email/name/picture from it
     *  instead of paying a second verification round trip. */
    claims: DecodedIdToken;
  }
}

// Bearer header is the normal path; `?token=` exists because a browser WebSocket cannot set headers.
function tokenFrom(req: { headers: IncomingMessage['headers']; url?: string }): string | null {
  const header = req.headers.authorization;
  if (header?.startsWith('Bearer ')) return header.slice(7).trim() || null;
  if (req.url) {
    const q = new URL(req.url, 'http://localhost').searchParams.get('token');
    if (q) return q.trim() || null;
  }
  return null;
}

async function verify(req: {
  headers: IncomingMessage['headers'];
  url?: string;
}): Promise<DecodedIdToken> {
  const token = tokenFrom(req);
  if (!token) throw new HttpError(401, 'missing_token');
  try {
    return await verifyIdToken(token);
  } catch {
    throw new HttpError(401, 'invalid_token');
  }
}

export const requireAuth: preHandlerHookHandler = async (req) => {
  const claims = await verify(req);
  req.uid = claims.uid;
  req.claims = claims;
};

/** For the WebSocket upgrade, which has no FastifyRequest. Throws HttpError(401). */
export async function uidFromRequest(req: IncomingMessage): Promise<string> {
  return (await verify(req)).uid;
}
