import { describe, it, expect, vi } from 'vitest';

/**
 * V8 — `authorizeOverlapMessage` (the computedBy === socket-uid assertion).
 *
 * This is the security boundary that prevents a client from forging another
 * uid as the overlap writer. The WS handler calls this before persisting or
 * pushing FCM; a mismatched `computedBy` must skip both.
 *
 * We mock ../overlap.js so parseOverlapMessage is a passthrough and we can
 * feed arbitrary envelopes; handleOverlapMessage is NOT exercised here (it
 * has its own suite in overlap.test.ts). The goal is to prove the gate.
 */

vi.mock('../firebase.js', () => ({
  getAuth: () => ({ verifyIdToken: vi.fn() }),
  initFirebaseAdmin: vi.fn(),
  getMessaging: vi.fn(),
  isFirebaseReady: () => true,
}));

vi.mock('../config.js', () => ({
  getConfig: () => ({
    databaseUrl: 'postgres://test',
    firebaseProjectId: 'test',
    firebaseServiceAccountJson: '{}',
    domain: 'api.test',
    port: 3000,
    adminToken: '',
  }),
  loadConfig: () => ({
    databaseUrl: 'postgres://test',
    firebaseProjectId: 'test',
    firebaseServiceAccountJson: '{}',
    domain: 'api.test',
    port: 3000,
    adminToken: '',
  }),
}));

vi.mock('../db.js', () => ({
  query: vi.fn(),
  getPool: () => ({ query: vi.fn(), connect: () => ({ query: vi.fn(), release: vi.fn() }) }),
  endPool: vi.fn(),
}));

import { authorizeOverlapMessage } from '../routes/sync.js';

const SOCKET_UID = 'uid-alex';

function overlapEnvelope(overrides: Record<string, unknown> = {}) {
  return {
    t: 'overlap',
    coupleId: 'cpl-1',
    windows: [{ startUtc: 0, endUtc: 60000, durationMinutes: 1, score: 0.5, reasonableBoth: true }],
    inputHash: 'hash-1',
    computedBy: SOCKET_UID,
    ...overrides,
  };
}

describe('authorizeOverlapMessage', () => {
  it('accepts a message whose computedBy matches the socket uid', () => {
    const out = authorizeOverlapMessage(overlapEnvelope(), SOCKET_UID);
    expect(out).not.toBeNull();
    expect(out?.msg.computedBy).toBe(SOCKET_UID);
    expect(out?.msg.coupleId).toBe('cpl-1');
  });

  it('rejects a forged computedBy (mismatched uid) — returns null', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const out = authorizeOverlapMessage(
      overlapEnvelope({ computedBy: 'uid-someone-else' }),
      SOCKET_UID
    );
    expect(out).toBeNull();
    expect(warn).toHaveBeenCalledTimes(1);
    expect(warn.mock.calls[0][0]).toContain('uid-someone-else');
    warn.mockRestore();
  });

  it('rejects when computedBy is empty (even if socket uid is also empty — envelope parse rejects first)', () => {
    // parseOverlapMessage rejects empty computedBy, so this never reaches the
    // uid comparison. Confirm the gate still returns null.
    const out = authorizeOverlapMessage(
      overlapEnvelope({ computedBy: '' }),
      SOCKET_UID
    );
    expect(out).toBeNull();
  });

  it('rejects a non-overlap envelope (wrong t) — returns null', () => {
    const out = authorizeOverlapMessage({ t: 'block:set', block: {} }, SOCKET_UID);
    expect(out).toBeNull();
  });

  it('rejects a malformed envelope (missing coupleId) — returns null', () => {
    const out = authorizeOverlapMessage(
      { t: 'overlap', windows: [], inputHash: 'h', computedBy: SOCKET_UID },
      SOCKET_UID
    );
    expect(out).toBeNull();
  });

  it('does not accept a partner-uid computedBy even when both are couple members', () => {
    // The authed socket is uid-alex; the partner is uid-sam. A message
    // claiming computedBy=uid-sam must be rejected — only the caller's own
    // uid is valid as the writer.
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const out = authorizeOverlapMessage(
      overlapEnvelope({ computedBy: 'uid-sam' }),
      SOCKET_UID
    );
    expect(out).toBeNull();
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });
});
