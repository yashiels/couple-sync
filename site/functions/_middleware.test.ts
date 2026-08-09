// The routing decision is the one piece of the site that can silently break the product: a page
// path misclassified as API returns a 401 JSON body instead of HTML, and an API path misclassified
// as page returns HTML to the app. These cases pin every live Fastify route (and the page paths)
// to the expected side of the split.
import { describe, expect, it } from 'vitest';
import { isApiPath } from './_middleware';

describe('isApiPath', () => {
  it.each([
    '/health',
    '/sync',
    '/auth/verify',
    '/auth/fcm-token',
    '/users/me',
    '/users/some-uid',
    '/couples/abc',
    '/couples/abc/unpair',
    '/invites',
    '/invites/ABC123/redeem',
    '/blocks',
    '/blocks/some-id',
    '/blocks/google',
    '/overlaps/latest',
    '/admin/cleanup',
  ])('treats API path %s as API', (path) => {
    expect(isApiPath(path)).toBe(true);
  });

  it.each([
    '/',
    '/index.html',
    '/style.css',
    '/privacy',
    '/privacy/',
    '/support',
    '/support/',
    '/invite',
    '/invite/ABC123',
    '/invite/ABC123/',
    '/favicon.ico',
  ])('treats page path %s as static', (path) => {
    expect(isApiPath(path)).toBe(false);
  });

  it('does not proxy a bare /invites/<code>', () => {
    // Only the /redeem suffix is a live API route; a bare code is not one, so it must not reach the
    // tunnel (it would 404 on the backend and blur the page split).
    expect(isApiPath('/invites/ABC123')).toBe(false);
  });
});
