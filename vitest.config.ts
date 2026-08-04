import { defineConfig } from 'vitest/config';

// Vitest's default include is `**/*.{test,spec}.?(c|m)[jt]s?(x)`, which walks into backend/src and
// fails: the app CI job never installs backend dependencies. App tests only.
export default defineConfig({ test: { include: ['src/**/*.test.ts'], environment: 'node' } });
