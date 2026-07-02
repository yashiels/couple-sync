#!/usr/bin/env bash
# Deploy to a managed Docker platform (Coolify): push the branch, Coolify builds
# the image from backend/Dockerfile + docker-compose.yml and rolls the container.
# Migrations run on start (Dockerfile CMD). Self-managed VPS fallback: see
# backend/README.md.
set -euo pipefail
BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
git push origin "$BRANCH"
echo "✓ Pushed $BRANCH — watch the Coolify build log, then curl https://<api-domain>/health"
