#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Configure Flutter for Firebase ==="
echo ""

# -------------------------------------------------------
# 1. Ensure flutterfire CLI is installed
# -------------------------------------------------------
echo "Checking for flutterfire CLI..."

if ! command -v flutterfire &>/dev/null; then
  echo "flutterfire CLI not found. Installing via dart pub global activate..."
  dart pub global activate flutterfire_cli
  echo "flutterfire CLI installed."
else
  echo "flutterfire CLI is already installed."
fi

echo ""

# -------------------------------------------------------
# 2. Run flutterfire configure
# -------------------------------------------------------
echo "Running flutterfire configure for project nexion-ai-prod..."
cd "$PROJECT_ROOT"
flutterfire configure --project=nexion-ai-prod

echo ""

# -------------------------------------------------------
# 3. Verify generated files
# -------------------------------------------------------
echo "Verifying generated configuration files..."

ANDROID_CONFIG="$PROJECT_ROOT/android/app/google-services.json"
IOS_CONFIG="$PROJECT_ROOT/ios/Runner/GoogleService-Info.plist"

MISSING=0

if [ -f "$ANDROID_CONFIG" ]; then
  echo "  google-services.json      ... OK ($ANDROID_CONFIG)"
else
  echo "  google-services.json      ... MISSING (expected at $ANDROID_CONFIG)"
  MISSING=1
fi

if [ -f "$IOS_CONFIG" ]; then
  echo "  GoogleService-Info.plist  ... OK ($IOS_CONFIG)"
else
  echo "  GoogleService-Info.plist  ... MISSING (expected at $IOS_CONFIG)"
  MISSING=1
fi

echo ""

if [ "$MISSING" -eq 0 ]; then
  echo "SUCCESS: Flutter Firebase configuration complete."
else
  echo "WARNING: One or more configuration files were not generated."
  echo "Re-run this script or check the flutterfire output above for errors."
  exit 1
fi
