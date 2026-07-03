import { query } from './db.js';

/**
 * Error thrown when a user is not a member of a couple. statusCode mirrors
 * the HTTP code the route handlers return.
 */
export class ForbiddenError extends Error {
  statusCode = 403 as const;
  constructor(message: string) {
    super(message);
    this.name = 'ForbiddenError';
  }
}

export interface CoupleRow {
  id: string;
  user_a_uid: string;
  user_b_uid: string;
  status: string;
  paired_at: number;
  created_at: number;
  unpair_history: unknown[];
}

/**
 * Load a couple row or throw 404 (as NotFoundError). Reused by the
 * membership check + the GET /couples/:id route.
 */
export class NotFoundError extends Error {
  statusCode = 404 as const;
  constructor(message: string) {
    super(message);
    this.name = 'NotFoundError';
  }
}

export async function getCoupleOr404(coupleId: string): Promise<CoupleRow> {
  const res = await query<CoupleRow>(
    'SELECT id, user_a_uid, user_b_uid, status, paired_at, created_at, unpair_history FROM couples WHERE id = $1',
    [coupleId]
  );
  if (res.rows.length === 0) {
    throw new NotFoundError(`Couple not found: ${coupleId}`);
  }
  return res.rows[0];
}

/**
 * Assert that `uid` is a member of `coupleId` (user_a_uid or user_b_uid).
 * Throws 403 ForbiddenError otherwise. Also throws 404 if the couple does
 * not exist (so a caller probing arbitrary ids cannot distinguish
 * "not yours" from "does not exist" — both surface as 403 here to avoid
 * leaking existence; the GET /couples/:id route surfaces 404 explicitly
 * only after the membership check passes... but per the spec we want
 * membership enforced first, so non-members get 403 even for missing
 * couples).
 */
export async function assertMember(coupleId: string, uid: string): Promise<CoupleRow> {
  let couple: CoupleRow;
  try {
    couple = await getCoupleOr404(coupleId);
  } catch (err) {
    // Non-existent couple → 403 to avoid leaking existence to non-members.
    if (err instanceof NotFoundError) {
      throw new ForbiddenError('Not a member of this couple');
    }
    throw err;
  }
  if (couple.user_a_uid !== uid && couple.user_b_uid !== uid) {
    throw new ForbiddenError('Not a member of this couple');
  }
  return couple;
}
