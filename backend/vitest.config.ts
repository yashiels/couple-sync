import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
    // Each file gets its own module registry so the in-memory socket map and fake db
    // never leak between suites.
    isolate: true,
  },
});
