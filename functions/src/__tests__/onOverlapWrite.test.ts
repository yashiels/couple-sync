import { handleOnOverlapWrite, filterInvalidFcmTokens, validateWindows } from '../onOverlapWrite';
import { CoupleDoc, OverlapWindow } from '../lib/types';

// Silence firebase-functions logger in unit tests
jest.mock('firebase-functions', () => ({
  logger: { warn: jest.fn(), info: jest.fn(), error: jest.fn() },
}));

const makeCouple = (): CoupleDoc => ({
  userAUid: 'userA',
  userBUid: 'userB',
  status: 'active',
  pairedAt: 0,
  createdAt: 0,
});

const makeWindow = (): OverlapWindow => ({
  startUtc: Date.now() + 3_600_000,
  endUtc: Date.now() + 7_200_000,
  durationMinutes: 60,
  score: 15,
  reasonableBoth: true,
});

const makeDeps = (overrides: Record<string, unknown> = {}) => ({
  getCouple: jest.fn().mockResolvedValue(makeCouple()),
  getFcmTokens: jest.fn()
    .mockResolvedValueOnce(['token-a1', 'token-a2'])
    .mockResolvedValueOnce(['token-b1']),
  sendNotification: jest.fn().mockResolvedValue([]),
  updateFcmTokens: jest.fn().mockResolvedValue(undefined),
  ...overrides,
});

describe('handleOnOverlapWrite', () => {
  test('sends notifications to both partners', async () => {
    const deps = makeDeps();
    await handleOnOverlapWrite('couple1', [makeWindow()], deps);

    expect(deps.getFcmTokens).toHaveBeenCalledWith('userA');
    expect(deps.getFcmTokens).toHaveBeenCalledWith('userB');
    expect(deps.sendNotification).toHaveBeenCalledTimes(2);
  });

  test('does nothing when no overlap windows', async () => {
    const deps = makeDeps();
    await handleOnOverlapWrite('couple1', [], deps);

    expect(deps.sendNotification).not.toHaveBeenCalled();
  });

  test('does nothing when couple not found', async () => {
    const deps = makeDeps({ getCouple: jest.fn().mockResolvedValue(null) });
    await handleOnOverlapWrite('couple1', [makeWindow()], deps);

    expect(deps.sendNotification).not.toHaveBeenCalled();
  });

  test('skips notification when user has no FCM tokens', async () => {
    const deps = makeDeps({
      getFcmTokens: jest.fn()
        .mockResolvedValueOnce([])       // userA has no tokens
        .mockResolvedValueOnce(['tok-b']),
    });
    await handleOnOverlapWrite('couple1', [makeWindow()], deps);

    // Only notifies userB since userA has no tokens
    expect(deps.sendNotification).toHaveBeenCalledTimes(1);
  });

  test('prunes invalid FCM tokens from userA after failed send', async () => {
    const deps = makeDeps({
      sendNotification: jest.fn()
        .mockResolvedValueOnce(['token-a2'])  // token-a2 is invalid for userA
        .mockResolvedValueOnce([]),
    });
    await handleOnOverlapWrite('couple1', [makeWindow()], deps);

    expect(deps.updateFcmTokens).toHaveBeenCalledWith('userA', ['token-a1']);
  });

  test('does not update FCM tokens when all are valid', async () => {
    const deps = makeDeps({
      sendNotification: jest.fn().mockResolvedValue([]),
    });
    await handleOnOverlapWrite('couple1', [makeWindow()], deps);

    expect(deps.updateFcmTokens).not.toHaveBeenCalled();
  });

  test('sends notification with title and body', async () => {
    const deps = makeDeps();
    await handleOnOverlapWrite('couple1', [makeWindow()], deps);

    expect(deps.sendNotification).toHaveBeenCalledWith(
      expect.any(Array),
      expect.objectContaining({
        title: expect.any(String),
        body: expect.any(String),
      })
    );
  });
});

describe('filterInvalidFcmTokens', () => {
  test('does NOT include token with transient error code in invalid list', () => {
    const tokens = ['token-transient', 'token-invalid'];
    const responses = [
      { success: false, error: { code: 'messaging/quota-exceeded' } },
      { success: false, error: { code: 'messaging/registration-token-not-registered' } },
    ];

    const invalid = filterInvalidFcmTokens(tokens, responses);

    expect(invalid).not.toContain('token-transient');
  });

  test('DOES include token with hard-invalid error code in invalid list', () => {
    const tokens = ['token-transient', 'token-invalid'];
    const responses = [
      { success: false, error: { code: 'messaging/quota-exceeded' } },
      { success: false, error: { code: 'messaging/registration-token-not-registered' } },
    ];

    const invalid = filterInvalidFcmTokens(tokens, responses);

    expect(invalid).toContain('token-invalid');
  });

  test('returns only hard-invalid tokens from mixed FCM response', () => {
    const tokens = ['token-ok', 'token-quota', 'token-unregistered'];
    const responses = [
      { success: true },
      { success: false, error: { code: 'messaging/quota-exceeded' } },
      { success: false, error: { code: 'messaging/registration-token-not-registered' } },
    ];

    const invalid = filterInvalidFcmTokens(tokens, responses);

    expect(invalid).toEqual(['token-unregistered']);
  });
});

describe('validateWindows', () => {
  const ok = (over: Partial<any> = {}) => ({
    startUtc: 1000, endUtc: 1000 + 60 * 60 * 1000, durationMinutes: 60, score: 5, reasonableBoth: true, ...over,
  });

  test('accepts well-formed windows', () => {
    expect(validateWindows([ok()])).toHaveLength(1);
  });
  test('rejects durationMinutes > 1560 (DST fall-back guard)', () => {
    expect(() => validateWindows([ok({ durationMinutes: 1561, endUtc: 1000 + 1561 * 60 * 1000 })])).toThrow();
  });
  test('rejects startUtc >= endUtc', () => {
    expect(() => validateWindows([ok({ startUtc: 2000, endUtc: 2000 })])).toThrow();
  });
  test('rejects end-start != durationMinutes*60000', () => {
    expect(() => validateWindows([ok({ durationMinutes: 30 })])).toThrow();
  });
  test('rejects non-bool reasonableBoth', () => {
    expect(() => validateWindows([ok({ reasonableBoth: 'yes' })])).toThrow();
  });
});

describe('handleOnOverlapWrite skips writer', () => {
  test('does not send to computedBy uid', async () => {
    const sent: string[] = [];
    await handleOnOverlapWrite('c1', [{
      startUtc: 1000, endUtc: 1000 + 60 * 60 * 1000, durationMinutes: 60, score: 5, reasonableBoth: true,
    }], {
      getCouple: async () => ({ userAUid: 'uA', userBUid: 'uB', status: 'active', pairedAt: 0, createdAt: 0 }),
      getFcmTokens: async (uid: string) => uid === 'uA' ? ['tA'] : ['tB'],
      sendNotification: async (tokens: string[]) => { sent.push(...tokens); return []; },
      updateFcmTokens: async () => {},
      // computedBy carried on the doc; the handler reads it.
    } as any, 'uA');
    expect(sent).toEqual(['tB']); // uA (writer) skipped
  });
});
