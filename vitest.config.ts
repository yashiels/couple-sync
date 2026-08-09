import { defineConfig } from 'vitest/config';

// Vitest's default include is `**/*.{test,spec}.?(c|m)[jt]s?(x)`, which walks into backend/src and
// fails: the app CI job never installs backend dependencies. App tests, plus the site's routing
// test (site/functions) — the site has no runtime deps, so its test runs on the app's install.
export default defineConfig({
  test: { include: ['src/**/*.test.ts', 'site/**/*.test.ts'], environment: 'node' },
});
