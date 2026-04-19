import { handleOnInviteCreate } from '../onInviteCreate';

describe('handleOnInviteCreate', () => {
  test('generates deep link URL from invite code', async () => {
    const updateDeepLink = jest.fn().mockResolvedValue(undefined);
    await handleOnInviteCreate('ABC123', { updateDeepLink });

    expect(updateDeepLink).toHaveBeenCalledWith(
      'ABC123',
      'https://coupleschedule.app/invite/ABC123'
    );
  });

  test('deep link URL contains the exact invite code', async () => {
    const updateDeepLink = jest.fn().mockResolvedValue(undefined);
    const code = 'XYZ789';
    await handleOnInviteCreate(code, { updateDeepLink });

    const [savedCode, savedUrl] = updateDeepLink.mock.calls[0] as [string, string];
    expect(savedCode).toBe(code);
    expect(savedUrl).toContain(code);
  });

  test('uses https://coupleschedule.app scheme (Universal Links / App Links)', async () => {
    const updateDeepLink = jest.fn().mockResolvedValue(undefined);
    await handleOnInviteCreate('TEST01', { updateDeepLink });

    const [, savedUrl] = updateDeepLink.mock.calls[0] as [string, string];
    expect(savedUrl).toMatch(/^https:\/\/coupleschedule\.app\/invite\//);
  });

  test('calls updateDeepLink exactly once per invite', async () => {
    const updateDeepLink = jest.fn().mockResolvedValue(undefined);
    await handleOnInviteCreate('CODE1', { updateDeepLink });

    expect(updateDeepLink).toHaveBeenCalledTimes(1);
  });
});
