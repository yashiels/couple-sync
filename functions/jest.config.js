/** @type {import('jest').Config} */
module.exports = {
  testEnvironment: 'node',
  testMatch: ['**/src/__tests__/**/*.test.ts'],
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
