#!/usr/bin/env bash
# Full authenticated E2E run. Executes INSIDE a mingc/android-build-box container with --network host
# (node + adb + java), against the on-Atlas stack (Auth emulator :9099, backend :3000, emulator 5554).
# See e2e/README.md for the docker run wrapper. Screenshots land in the mounted out dir.
set -euo pipefail

REPO="${REPO:-/app}"
AUTH="${AUTH_EMULATOR_URL:-http://127.0.0.1:9099}"
API="${BACKEND_URL:-http://127.0.0.1:3000}"
export PATH="/opt/android-sdk/platform-tools:$HOME/.maestro/bin:$PATH"
cd "$REPO"

echo "== ensure maestro + adb =="
command -v maestro >/dev/null 2>&1 || { curl -Ls https://get.maestro.mobile.dev | bash >/tmp/mi.log 2>&1; export PATH="$HOME/.maestro/bin:$PATH"; }
adb connect 127.0.0.1:5555 >/dev/null 2>&1 || true
adb devices

echo "== flow 1: login + timezone + pairing screen =="
maestro test e2e/maestro/01-login-timezone.yaml

echo "== seed partner u2 + invite code =="
PAIR_CODE="$(node e2e/seed-partner.mjs invite u2@e2e.test e2e-password | sed -n 's/^PAIR_CODE=//p' | tr -d '\r')"
[ -n "$PAIR_CODE" ] || { echo "no PAIR_CODE from seed"; exit 1; }
echo "PAIR_CODE=$PAIR_CODE"

echo "== flow 2: enter code + pair =="
maestro test --env PAIR_CODE="$PAIR_CODE" e2e/maestro/02-pair.yaml

echo "== fetch u1 couple_id (sign in u1 -> /auth/verify) =="
U1_TOK="$(curl -s -X POST "$AUTH/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake" \
  -H 'Content-Type: application/json' -d '{"email":"u1@e2e.test","password":"e2e-password","returnSecureToken":true}' \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).idToken||""))')"
CID="$(curl -s -X POST "$API/auth/verify" -H "Authorization: Bearer $U1_TOK" \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).user?.couple_id||""))')"
[ -n "$CID" ] || { echo "no couple_id after pairing"; exit 1; }
echo "couple_id=$CID"

echo "== seed busy fence blocks -> one window Mon 10 Aug 2026 18:00-20:00 UTC =="
# u1 busy up to the gap start; u2 busy from the gap end. Intersection of free gaps = the window.
node e2e/seed-partner.mjs block --couple-id="$CID" --type=busy --title="Busy" --timezone=Etc/UTC \
  --start=1785542400000 --end=1786384800000 u1@e2e.test e2e-password
node e2e/seed-partner.mjs block --couple-id="$CID" --type=busy --title="Busy" --timezone=Etc/UTC \
  --start=1786392000000 --end=1788220800000 u2@e2e.test e2e-password

echo "== flow 3: assert overlap window renders =="
maestro test e2e/maestro/03-overlap.yaml

echo "== E2E PASSED =="
