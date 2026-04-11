#!/usr/bin/env bash
set -euo pipefail

echo "=== Deploy Firestore Rules & Indexes ==="
echo ""

# -------------------------------------------------------
# Deploy Firestore rules and indexes
# -------------------------------------------------------
echo "Deploying Firestore security rules and indexes to nexion-ai-prod..."
firebase deploy --only firestore --project nexion-ai-prod
echo ""
echo "=== Firestore rules and indexes deployed successfully ==="
