#!/usr/bin/env bash
# Runs ON Atlas (rsynced to ~/apps/couple-sync by the atlas-deploy CI workflow). Builds +
# (re)deploys the couple-sync stack (db + api + cloudflared tunnel) from the rsynced ./backend
# source. Secrets stay in the local .env, rendered once from atlas.env.tpl via `op inject` and
# NEVER rsynced/committed. Mirrors llm-gateway/atlas-deploy.sh.
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || {
  echo "no .env on Atlas — render it once from atlas.env.tpl, e.g.:" >&2
  echo "  op inject -i atlas.env.tpl -o .env && chmod 600 .env" >&2
  exit 1
}

# Never --remove-orphans: other stacks (llm-gateway, portainer) coexist on Atlas.
docker compose -p couple-sync --env-file .env -f compose.atlas.yml up -d --build
docker image prune -f >/dev/null 2>&1 || true

echo "=== deployed ==="
docker compose -p couple-sync -f compose.atlas.yml ps
