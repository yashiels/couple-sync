"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const onInviteCreate_1 = require("../onInviteCreate");
describe('handleOnInviteCreate', () => {
    test('generates deep link URL from invite code', async () => {
        const updateDeepLink = jest.fn().mockResolvedValue(undefined);
        await (0, onInviteCreate_1.handleOnInviteCreate)('ABC123', { updateDeepLink });
        expect(updateDeepLink).toHaveBeenCalledWith('ABC123', 'coupleschedule://invite/ABC123');
    });
    test('deep link URL contains the exact invite code', async () => {
        const updateDeepLink = jest.fn().mockResolvedValue(undefined);
        const code = 'XYZ789';
        await (0, onInviteCreate_1.handleOnInviteCreate)(code, { updateDeepLink });
        const [savedCode, savedUrl] = updateDeepLink.mock.calls[0];
        expect(savedCode).toBe(code);
        expect(savedUrl).toContain(code);
    });
    test('uses coupleschedule:// scheme', async () => {
        const updateDeepLink = jest.fn().mockResolvedValue(undefined);
        await (0, onInviteCreate_1.handleOnInviteCreate)('TEST01', { updateDeepLink });
        const [, savedUrl] = updateDeepLink.mock.calls[0];
        expect(savedUrl).toMatch(/^coupleschedule:\/\//);
    });
    test('calls updateDeepLink exactly once per invite', async () => {
        const updateDeepLink = jest.fn().mockResolvedValue(undefined);
        await (0, onInviteCreate_1.handleOnInviteCreate)('CODE1', { updateDeepLink });
        expect(updateDeepLink).toHaveBeenCalledTimes(1);
    });
});
//# sourceMappingURL=onInviteCreate.test.js.map