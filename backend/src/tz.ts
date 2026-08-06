import { IANAZone } from 'luxon';

/**
 * IANA ids only (§8). Not just `IANAZone.isValidZone`: that accepts a fixed offset such as
 * '+02:00', because ECMA-402 does, and an offset carries no DST rules — so a user who stored
 * '+02:00' would get correct windows today and silently wrong ones after any transition. Two
 * callers today (PATCH /users/:uid, invite redeem) and every block write in Task 7.
 */
export function isValidTimezone(zone: unknown): zone is string {
  return typeof zone === 'string' && !/^[+-]/.test(zone) && IANAZone.isValidZone(zone);
}
