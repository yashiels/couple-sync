module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
  ],
  parser: '@typescript-eslint/parser',
  parserOptions: {
    project: ['tsconfig.eslint.json'],
    sourceType: 'module',
  },
  ignorePatterns: [
    '/lib/**/*',  // Ignore built files
    '/node_modules/**/*',
    '.eslintrc.js',  // JS config files not in tsconfig
    'jest.config.js',
  ],
  plugins: [
    '@typescript-eslint',
  ],
  rules: {
    // Relaxed rules for pragmatic development
    '@typescript-eslint/no-explicit-any': 'warn',
    '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
  },
};
