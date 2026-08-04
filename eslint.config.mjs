import expo from 'eslint-config-expo/flat.js';

// backend/ has its own tsconfig, its own package manager, and no lint script — linting it from here
// would resolve the wrong deps. dist/, android/ and ios/ are build output.
export default [...expo, { ignores: ['backend/**', 'dist/**', 'android/**', 'ios/**'] }];
