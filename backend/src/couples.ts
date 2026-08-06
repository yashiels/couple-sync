import { query } from './db.js';
import { HttpError } from './http.js';
import type { CoupleRow } from './wire.js';

// The one guard every couple-scoped path goes through. A non-existent couple answers 403 exactly
// like a non-member one, so the API never leaks whether an id exists.
export async function assertMember(coupleId: string, uid: string): Promise<CoupleRow> {
  const [couple] = await query<CoupleRow>('SELECT * FROM couples WHERE id = $1', [coupleId]);
  if (!couple || couple.status !== 'active') throw new HttpError(403, 'forbidden');
  if (couple.user_a_uid !== uid && couple.user_b_uid !== uid) throw new HttpError(403, 'forbidden');
  return couple;
}

export function partnerUid(couple: CoupleRow, uid: string): string {
  return couple.user_a_uid === uid ? couple.user_b_uid : couple.user_a_uid;
}
