#!/usr/bin/env bash
#
# deploy.sh — Couple Sync VPS deploy (spec §10).
#
# Idempotent + safe to re-run. Pulls latest from the current branch on the VPS,
# rebuilds the api + postgres + caddy stack, and applies DB migrations.
#
# Usage:
#   VPS_HOST=user@your-vps-host ./deploy.sh
#   VPS_HOST=user@1.2.3.4 ./deploy.sh
#
# Env:
#   VPS_HOST       (required) — ssh destination for the VPS.
#   VPS_PATH       (optional) — repo path on the VPS (default /opt/couple-sync).
#   SSH_OPTS       (optional) — extra args passed to ssh.
#
# Exit codes:
#   0  success
#   1  generic failure (ssh unreachable, git pull failed, build failed)
#   2  missing VPS_HOST
#
set -euo pipefail

VPS_HOST="${VPS_HOST:-}"
VPS_PATH="${VPS_PATH:-/opt/couple-sync}"
SSH_OPTS="${SSH_OPTS:-}"

if [[ -z "$VPS_HOST" ]]; then
  echo "ERROR: VPS_HOST is not set. Usage: VPS_HOST=user@host ./deploy.sh" >&2
  exit 2
fi

# shellcheck disable=SC2086
SSH=(ssh $SSH_OPTS "$VPS_HOST")

echo "→ Deploying to $VPS_HOST:$VPS_PATH"

# 1. Ensure the repo dir exists on the VPS (first-time bootstrap).
if ! "${SSH[@]}" "test -d $VPS_PATH/.git"; then
  echo "ERROR: $VPS_PATH is not a git checkout on the VPS." >&2
  echo "       Bootstrap once: ssh $VPS_HOST 'sudo mkdir -p $VPS_PATH && sudo chown -R \$USER \$VPS_PATH && git clone <repo-url> $VPS_PATH'" >&2
  exit 1
fi

# 2. Pull latest. We do NOT force — a dirty tree on the VPS is a human error
#    that should be resolved manually, not clobbered by the deploy script.
echo "→ git pull"
"${SSH[@]}" "cd $VPS_PATH && git pull --ff-only"

# 3. Rebuild + restart the stack. --build ensures image freshness; -d detaches.
echo "→ docker compose up -d --build"
"${SSH[@]}" "cd $VPS_PATH && docker compose up -d --build"

# 4. Wait for postgres to be healthy, then run migrations inside the api
#    container. The api service depends_on postgres (healthy), so by the time
#    `up -d` returns the DB is accepting connections — but re-check explicitly.
echo "→ waiting for postgres to be healthy"
"${SSH[@]}" "cd $VPS_PATH && timeout 60 sh -c 'until docker compose ps postgres | grep -q \"healthy\"; do sleep 2; done'"

echo "→ pnpm migrate"
"${SSH[@]}" "cd $VPS_PATH && docker compose exec -T api pnpm migrate"

echo "✓ Deploy complete. Stack status:"
"${SSH[@]}" "cd $VPS_PATH && docker compose ps"
