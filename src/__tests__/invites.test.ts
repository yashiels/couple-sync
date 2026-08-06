import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import { normalizeInviteCode, redeemErrorMessage } from '../invites';

describe('normalizeInviteCode', () => {
  it('upper-cases as the user types, so the field matches the code they were given', () => {
    expect(normalizeInviteCode('abc234')).toBe('ABC234');
  });

  it('drops the four characters the generator never emits', () => {
    // O, 0, I and 1 are excluded from the alphabet (backend/src/routes/invites.ts) because they are
    // misread; typing one is therefore always a mistake, not a code.
    expect(normalizeInviteCode('OoIi01')).toBe('');
  });

  it('drops spaces, punctuation and anything else the keyboard produces', () => {
    expect(normalizeInviteCode('ab -c/2 3')).toBe('ABC23');
  });

  it('never exceeds six characters', () => {
    expect(normalizeInviteCode('ABCDEFGH')).toBe('ABCDEF');
  });

  it('keeps every character the alphabet does contain', () => {
    expect(normalizeInviteCode('HJNPZ9')).toBe('HJNPZ9');
  });
});

describe('redeemErrorMessage', () => {
  const codes = [
    'unknown_code',
    'invite_expired',
    'invite_used',
    'self_pair',
    'already_paired',
    'inviter_already_paired',
    'timezone_required',
    'invalid_timezone',
    'unknown_user',
  ];

  it('covers every code the redeem route can throw', () => {
    // Read from the route itself: a new HttpError there must not silently fall through to the
    // generic message, and this is cheaper than discovering it on a device.
    const source = readFileSync(
      new URL('../../backend/src/routes/invites.ts', import.meta.url),
      'utf8',
    );
    const thrown = [...source.matchAll(/new HttpError\(4\d\d, '([a-z_]+)'\)/g)].map((m) => m[1]);
    expect(thrown.length).toBeGreaterThan(0);
    for (const code of new Set(thrown)) expect(codes).toContain(code);
  });

  it('gives a different message for each of the five distinct situations', () => {
    const messages = [
      'invite_expired',
      'invite_used',
      'self_pair',
      'already_paired',
      'inviter_already_paired',
    ].map((code) => redeemErrorMessage(code, 409));
    expect(new Set(messages).size).toBe(5);
  });

  it('names a next action in every mapped message', () => {
    for (const code of codes) {
      const message = redeemErrorMessage(code, 409);
      expect(message).not.toContain(code);
      expect(message.length).toBeGreaterThan(20);
    }
  });

  it('reports a transport failure as a connection problem, not as a bad code', () => {
    // status 0 is ApiError's no-response case, where `code` is a fetch message rather than ours.
    expect(redeemErrorMessage('Network request failed', 0)).toMatch(/connection/i);
  });

  it('falls back to a message carrying the unmapped code', () => {
    expect(redeemErrorMessage('teapot', 418)).toContain('teapot');
  });
});
