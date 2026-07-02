/** @type {import('jest').Config} */
const includeRulesTests = process.env.JEST_INCLUDE_RULES === '1';

module.exports = {
  testEnvironment: 'node',
  testMatch: ['**/src/__tests__/**/*.test.ts'],
  testPathIgnorePatterns: includeRulesTests
    ? ['/node_modules/']
    : ['/node_modules/', '/src/__tests__/rules/'],
  collectCoverageFrom: ['src/**/*.ts', '!src/**/__tests__/**'],
  transform: {
    '^.+\\.ts$': [
      'ts-jest',
      {
        tsconfig: {
          strict: true,
          esModuleInterop: true,
          module: 'commonjs',
          target: 'es2017',
          skipLibCheck: true,
          noUnusedLocals: false,
          types: ['jest', 'node'],
        },
      },
    ],
  },
};
