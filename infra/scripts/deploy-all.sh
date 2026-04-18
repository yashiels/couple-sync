#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Deploy All ==="
echo ""

# -------------------------------------------------------
# 1. Deploy Cloud Functions
# -------------------------------------------------------
echo "--- Step 1: Deploying Cloud Functions ---"
"$SCRIPT_DIR/deploy-functions.sh"
echo ""

# -------------------------------------------------------
# 2. Deploy Firestore Rules & Indexes
# -------------------------------------------------------
echo "--- Step 2: Deploying Firestore Rules & Indexes ---"
"$SCRIPT_DIR/deploy-rules.sh"
echo ""

# -------------------------------------------------------
# Done
# -------------------------------------------------------
echo "============================================"
echo "  All deployments completed successfully!"
echo "============================================"
