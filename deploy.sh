#!/usr/bin/env bash
#
# deploy.sh — deploy Couple Sync to a managed Docker platform (Coolify).
#
# On Coolify, deployment is triggered by a git push: Coolify watches the branch,
# builds the Docker image from backend/Dockerfile + docker-compose.yml, and
# rolls the container. The container runs migrations on start (see Dockerfile
# CMD), so no separate migrate step is needed.
#
# Usage (push the current branch to trigger a Coolify build):
#   ./deploy.sh
#   ./deploy.sh main
#
# Self-managed VPS (no Coolify)? See backend/README.md → "Self-managed deploy"
# for the raw `docker compose up -d --build` flow (env-driven, no Caddy).
#
set -euo pipefail

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"

echo "→ Pushing $BRANCH to origin (Coolify will build + deploy on push)"
git push origin "$BRANCH"

cat <<EOF
✓ Pushed $BRANCH.

Next (in Coolify):
  - The application watching this branch will build automatically.
  - Confirm the build + container start in the Coolify deploy log.
  - Health check: curl https://<your-api-domain>/health

Migrations run automatically on container start (Dockerfile CMD runs
`node dist/migrate.js` before `node dist/index.js`).
EOF
