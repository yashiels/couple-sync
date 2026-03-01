module.exports = {
  root: true,
  env: {
    es2020: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
  ],
  parser: "@typescript-eslint/parser",
  plugins: ["@typescript-eslint"],
  ignorePatterns: [
    "/lib/**/*",
    "index.js",
  ],
  rules: {
    "quotes": ["error", "double"],
    "max-len": ["error", { code: 120 }],
    "no-unused-vars": "off",
    "@typescript-eslint/no-unused-vars": ["error"],
  },
};
