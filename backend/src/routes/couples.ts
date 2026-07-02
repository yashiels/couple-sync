import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { authenticate, type DecodedIdToken } from '../auth.js';
import { assertMember, type CoupleRow } from '../couples.js';

/**
 * Couple REST routes — V3.
 *
 * Wire shape (Flutter `CoupleModel.fromJson`): camelCase keys
 *   { userAUid, userBUid, status, pairedAt, unpairHistory, createdAt }
 */

function rowToJson(row: CoupleRow) {
  return {
    id: row.id,
    userAUid: row.user_a_uid,
    userBUid: row.user_b_uid,
    status: row.status,
    pairedAt: row.paired_at,
    unpairHistory: row.unpair_history,
    createdAt: row.created_at,
  };
}

async function getUid(request: FastifyRequest): Promise<string> {
  const attached = (request as any).user as DecodedIdToken | undefined;
  if (attached?.uid) return attached.uid;
  return (await authenticate(request)).uid;
}

function sendError(reply: FastifyReply, err: unknown) {
  const statusCode = (err as { statusCode?: number }).statusCode ?? 500;
  return reply.code(statusCode).send({
    error: statusCode === 403 ? 'forbidden' : statusCode === 404 ? 'not_found' : 'error',
    message: err instanceof Error ? err.message : 'Internal error',
  });
}

export const coupleRoutes: FastifyPluginAsync = async (app) => {
  // GET /couples/:id — return the couple doc. Membership enforced.
  app.get('/couples/:id', async (request: FastifyRequest, reply: FastifyReply) => {
    let uid: string;
    try {
      uid = await getUid(request);
    } catch (err) {
      return sendError(reply, err);
    }
    const { id } = request.params as { id: string };
    try {
      const couple = await assertMember(id, uid);
      return reply.code(200).send(rowToJson(couple));
    } catch (err) {
      return sendError(reply, err);
    }
  });
};

export default coupleRoutes;
