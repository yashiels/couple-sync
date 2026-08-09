import expo from 'eslint-config-expo/flat.js';

// backend/ has its own tsconfig, its own package manager, and no lint script — linting it from here
// would resolve the wrong deps. dist/, android/ and ios/ are build output.
export default [
  ...expo,
  // .worktrees/** holds sibling git worktrees (each a full checkout incl. its own backend/); linting
  // them here re-flags backend files with no backend deps installed and is not this checkout's job.
  { ignores: ['backend/**', 'dist/**', 'android/**', 'ios/**', '.worktrees/**'] },
];
