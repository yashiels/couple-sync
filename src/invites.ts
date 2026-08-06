/**
 * Invite-code text handling. Zero imports on purpose: this is the part of the pairing screen with
 * rules in it, and it stays testable without a React Native harness.
 */

export const CODE_LENGTH = 6;

/**
 * The generator's alphabet excludes O, 0, I and 1 (`backend/src/routes/invites.ts`) because the code
 * is read off one screen and typed into another. Anything else the keyboard produces is dropped as it
 * is typed, and the case is forced up: the server upper-cases what it receives, but the field must
 * show the user the same six characters they were given.
 */
export function normalizeInviteCode(input: string): string {
  return input
    .toUpperCase()
    .replace(/[^A-HJ-NP-Z2-9]/g, '')
    .slice(0, CODE_LENGTH);
}

/**
 * One message per code `POST /invites/:code/redeem` actually returns. These are five different
 * situations for the user, not one "invalid code" — a used code, an expired code, their own code, an
 * account already paired, and an inviter already paired each need a different next action.
 */
const REDEEM_MESSAGES: Record<string, string> = {
  unknown_code: 'That code does not exist. Check the six characters and try again.',
  invite_expired: 'That code has expired. Ask your partner to share a new one.',
  invite_used: 'That code has already been used.',
  self_pair: 'That is your own code — send it to your partner instead.',
  already_paired: 'You are already paired. Unpair in Settings before joining someone else.',
  inviter_already_paired:
    'Your partner has already paired with someone else. Ask them for a new code.',
  // Both mean the same thing to this user: the *other* side has no usable timezone, since the guard
  // chain already made this user set theirs before showing the pairing screen.
  timezone_required:
    'Your partner has not finished setting up yet. Ask them to open the app, then try again.',
  invalid_timezone:
    'Your partner has not finished setting up yet. Ask them to open the app, then try again.',
  unknown_user: 'Your account is not set up yet. Sign out and sign in again.',
  no_session: 'You are signed out. Sign in again to pair.',
};

/** `status` 0 is `ApiError`'s transport failure, where `code` is a fetch message, not a server code. */
export function redeemErrorMessage(code: string, status: number): string {
  if (status === 0) return 'Could not reach the server. Check your connection and try again.';
  return REDEEM_MESSAGES[code] ?? `Could not pair (${code}).`;
}
