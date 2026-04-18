import { handleOnOverlapWrite } from '../onOverlapWrite';
import { CoupleDoc, OverlapWindow } from '../lib/types';

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
