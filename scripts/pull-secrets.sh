#!/usr/bin/env bash
# Pull every local dev secret for couple-sync from 1Password (Nexion vault, item "couple-sync").
# Idempotent — safe to re-run. Requires the `op` CLI signed in (service account or `op signin`).
#
#   bash scripts/pull-secrets.sh
#
# Produces (all gitignored):
#   .env / backend/.env          app + backend env (via op inject on the .tpl files)
#   google-services.json         real Firebase Android config
#   GoogleService-Info.plist     real Firebase iOS config (Google Sign-In reversed-client scheme)
#   credentials/couple-sync.jks  release/debug signing keystore (SHA-1 registered in Firebase)
#   ~/.gradle/gradle.properties  CS_STORE_PASSWORD / CS_KEY_PASSWORD for the debug signingConfig
#
# After this, build with JDK 17:  JAVA_HOME=$(/usr/libexec/java_home -v 17) npm run android
set -euo pipefail

VAULT="Nexion"
ITEM="rn47nl5ayzg2cztuw4tmizbrvi" # "couple-sync" item, pinned by UUID
# Suppress the macOS desktop-app data-protection dialog when using a service account (see one-password skill).
export OP_LOAD_DESKTOP_APP_SETTINGS=false OP_BIOMETRIC_UNLOCK_ENABLED=false

cd "$(dirname "$0")/.."

command -v op >/dev/null || { echo "error: 1Password CLI (op) not found" >&2; exit 1; }
op whoami >/dev/null 2>&1 || { echo "error: op is not signed in (run 'op signin' or set OP_SERVICE_ACCOUNT_TOKEN)" >&2; exit 1; }

read_field() { op read "op://$VAULT/$ITEM/$1"; }

echo "1/5 env files"
op inject -f -i .env.tpl -o .env
[ -f backend/.env.tpl ] && op inject -f -i backend/.env.tpl -o backend/.env

echo "2/5 google-services.json (Android Firebase config)"
read_field google_services_json_b64 | base64 --decode > google-services.json

echo "3/5 GoogleService-Info.plist (iOS Firebase config)"
read_field google_services_info_plist_b64 | base64 --decode > GoogleService-Info.plist

echo "4/5 signing keystore -> credentials/couple-sync.jks"
mkdir -p credentials
read_field keystore_base64 | base64 --decode > credentials/couple-sync.jks

echo "5/5 signing passwords -> ~/.gradle/gradle.properties"
GP="$HOME/.gradle/gradle.properties"
mkdir -p "$HOME/.gradle"; touch "$GP"
SP="$(read_field keystore_password)"
KP="$(read_field key_password)"
# Replace any prior CS_ lines, then append the current values.
grep -v '^CS_STORE_PASSWORD=\|^CS_KEY_PASSWORD=' "$GP" > "$GP.tmp" 2>/dev/null || true
mv "$GP.tmp" "$GP"
printf 'CS_STORE_PASSWORD=%s\nCS_KEY_PASSWORD=%s\n' "$SP" "$KP" >> "$GP"
chmod 600 "$GP"

# JDK 17 is required — Android Gradle Plugin's jdkImage step fails on newer JDKs.
if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
  echo "warning: JDK 17 not found. Install it (macOS: brew install --cask temurin@17) and build with:" >&2
  echo "         JAVA_HOME=\$(/usr/libexec/java_home -v 17) npm run android" >&2
fi

echo "done. Build with:  JAVA_HOME=\$(/usr/libexec/java_home -v 17) npm run android"
