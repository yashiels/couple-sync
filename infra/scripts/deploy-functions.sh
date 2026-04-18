#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Deploy Cloud Functions ==="
echo ""

cd "$PROJECT_ROOT/functions"

# -------------------------------------------------------
# 1. Install dependencies
# -------------------------------------------------------
echo "Installing dependencies..."
npm ci
echo "Dependencies installed."
echo ""

# -------------------------------------------------------
# 2. Build
# -------------------------------------------------------
echo "Building TypeScript..."
npm run build
echo "Build complete."
echo ""

# -------------------------------------------------------
# 3. Lint
# -------------------------------------------------------
echo "Running linter..."
npm run lint
echo "Lint passed."
echo ""

# -------------------------------------------------------
# 4. Test
# -------------------------------------------------------
echo "Running tests..."
npm test
echo "Tests passed."
echo ""

# -------------------------------------------------------
# 5. Deploy
# -------------------------------------------------------
echo "Deploying Cloud Functions to nexion-ai-prod..."
firebase deploy --only functions --project nexion-ai-prod
echo ""
echo "=== Cloud Functions deployed successfully ==="
