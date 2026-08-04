import { query } from './db.js';
import type { CoupleRow, UserRow } from './dto.js';
import { HttpError } from './http.js';

// The one guard every couple-scoped path goes through. A non-existent couple answers 403 exactly
// like a non-member one, so the API never leaks whether an id exists.
export async function assertMember(coupleId: unknown, uid: string): Promise<CoupleRow> {
  if (typeof coupleId !== 'string' || !coupleId) throw new HttpError(403, 'forbidden');
  const [couple] = await query<CoupleRow>('SELECT * FROM couples WHERE id = $1', [coupleId]);
  if (!couple || couple.status !== 'active') throw new HttpError(403, 'forbidden');
  if (couple.user_a_uid !== uid && couple.user_b_uid !== uid) throw new HttpError(403, 'forbidden');
  return couple;
}

export function partnerUid(couple: CoupleRow, uid: string): string {
  return couple.user_a_uid === uid ? couple.user_b_uid : couple.user_a_uid;
}

export async function getUser(uid: string): Promise<UserRow | undefined> {
  const [row] = await query<UserRow>('SELECT * FROM users WHERE uid = $1', [uid]);
  return row;
}
